import SwiftUI
import DeltaCore
import Combine

enum GameState {
  case connecting
  case loggingIn
  case downloadingChunks(numberReceived: Int, total: Int)
  case playing
  case gpuFrameCaptureComplete(file: URL)
}

enum OverlayState {
  case menu
  case settings
}

class Box<T> {
  var value: T

  init(_ initialValue: T) {
    self.value = initialValue
  }
}

class GameViewModel: ObservableObject {
  @Published var state = StateWrapper<GameState>(initial: .connecting)
  @Published var overlayState = StateWrapper<OverlayState>(initial: .menu)

  var client: Client
  var inputDelegate: ClientInputDelegate
  var renderCoordinator: RenderCoordinator
  var downloadedChunksCount = Box(0)
  var serverDescriptor: ServerDescriptor

  var cancellables: [AnyCancellable] = []

  init(client: Client, inputDelegate: ClientInputDelegate, renderCoordinator: RenderCoordinator, serverDescriptor: ServerDescriptor) {
    self.client = client
    self.inputDelegate = inputDelegate
    self.renderCoordinator = renderCoordinator
    self.serverDescriptor = serverDescriptor

    client.eventBus.registerHandler { [weak self] event in
      guard let self = self else { return }
      self.handleClientEvent(event)
    }

    watch(state)
    watch(overlayState)
  }

  func watch<T: ObservableObject>(_ value: T) {
    self.cancellables.append(value.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    })
  }

  func closeMenu() {
    inputDelegate.keymap = ConfigManager.default.config.keymap
    inputDelegate.mouseSensitivity = ConfigManager.default.config.mouseSensitivity

    withAnimation(nil) {
      inputDelegate.captureCursor()
    }
  }

  func joinServer(_ descriptor: ServerDescriptor) {
    // Get the account to use
    guard let account = ConfigManager.default.config.selectedAccount else {
      log.error("Error, attempted to join server without a selected account.")
      DeltaClientApp.modalError("Please login and select an account before joining a server", safeState: .accounts)
      return
    }

    // Refresh the account (if it's an online account) and then join the server
    Task {
      let refreshedAccount: Account
      do {
        refreshedAccount = try await ConfigManager.default.getRefreshedAccount()
      } catch {
        let message = "Failed to refresh account '\(account.username)': \(error)"
        log.error(message)
        DeltaClientApp.modalError(message, safeState: .serverList)
        return
      }

      do {
        try self.client.joinServer(
          describedBy: descriptor,
          with: refreshedAccount)
      } catch {
        let message = "Failed to send join server request: \(error)"
        log.error(message)
        DeltaClientApp.modalError(message, safeState: .serverList)
      }
    }
  }

  func handleClientEvent(_ event: Event) {
    switch event {
      case let connectionFailedEvent as ConnectionFailedEvent:
        let serverName = serverDescriptor.host + (serverDescriptor.port != nil ? (":" + String(serverDescriptor.port!)) : "")
        DeltaClientApp.modalError("Connection to \(serverName) failed: \(connectionFailedEvent.networkError)", safeState: .serverList)
      case _ as LoginStartEvent:
        state.update(to: .loggingIn)
      case _ as JoinWorldEvent:
        // Approximation of the number of chunks the server will send (used in progress indicator)
        let totalChunksToReceieve = Int(pow(Double(client.game.maxViewDistance * 2 + 3), 2))
        state.update(to: .downloadingChunks(numberReceived: 0, total: totalChunksToReceieve))
      case _ as World.Event.AddChunk:
        ThreadUtil.runInMain {
          if case let .downloadingChunks(_, total) = state.current {
            // An intermediate variable is used to reduce the number of SwiftUI updates generated by downloading chunks
            downloadedChunksCount.value += 1
            if downloadedChunksCount.value % 25 == 0 {
              state.update(to: .downloadingChunks(numberReceived: downloadedChunksCount.value, total: total))
            }
          }
        }
      case _ as TerrainDownloadCompletionEvent:
        state.update(to: .playing)
      case let disconnectEvent as PlayDisconnectEvent:
        DeltaClientApp.modalError("Disconnected from server during play:\n\n\(disconnectEvent.reason)", safeState: .serverList)
      case let disconnectEvent as LoginDisconnectEvent:
        DeltaClientApp.modalError("Disconnected from server during login:\n\n\(disconnectEvent.reason)", safeState: .serverList)
      case let packetError as PacketHandlingErrorEvent:
        DeltaClientApp.modalError(
          "Failed to handle packet with id 0x\(String(packetError.packetId, radix: 16)):\n\n\(packetError.error)",
          safeState: .serverList
        )
      case let packetError as PacketDecodingErrorEvent:
        DeltaClientApp.modalError(
          "Failed to decode packet with id 0x\(String(packetError.packetId, radix: 16)):\n\n\(packetError.error)",
          safeState: .serverList
        )
      case let generalError as ErrorEvent:
        if let message = generalError.message {
          DeltaClientApp.modalError("\(message); \(generalError.error)")
        } else {
          DeltaClientApp.modalError("\(generalError.error)")
        }
      case .press(.performGPUFrameCapture) as InputEvent:
        let outputFile = StorageManager.default.getUniqueGPUCaptureFile()
        do {
          try renderCoordinator.captureFrames(count: 10, to: outputFile)
        } catch {
          DeltaClientApp.modalError("Failed to start frame capture: \(error)", safeState: .serverList)
        }
      case let event as FinishFrameCaptureEvent:
        inputDelegate.releaseCursor()
        state.update(to: .gpuFrameCaptureComplete(file: event.file))
      default:
        break
    }
  }
}

struct GameView: View {
  @EnvironmentObject var appState: StateWrapper<AppState>

  @ObservedObject var model: GameViewModel
  @Binding var cursorCaptured: Bool

  init(
    serverDescriptor: ServerDescriptor,
    resourcePack: ResourcePack,
    inputCaptureEnabled: Binding<Bool>,
    delegateSetter setDelegate: (InputDelegate) -> Void
  ) {
    let client = Client(resourcePack: resourcePack)
    client.configuration.render = ConfigManager.default.config.render

    // Setup input system
    let inputDelegate = ClientInputDelegate(for: client)
    setDelegate(inputDelegate)

    // Create render coordinator
    let renderCoordinator = RenderCoordinator(client)

    model = GameViewModel(
      client: client,
      inputDelegate: inputDelegate,
      renderCoordinator: renderCoordinator,
      serverDescriptor: serverDescriptor
    )

    _cursorCaptured = inputCaptureEnabled

    // Setup plugins
    DeltaClientApp.pluginEnvironment.addEventBus(client.eventBus)
    DeltaClientApp.pluginEnvironment.handleWillJoinServer(server: serverDescriptor, client: client)

    // Connect to server
    model.joinServer(serverDescriptor)
  }

  var body: some View {
    Group {
      switch model.state.current {
        case .connecting:
          connectingView
        case .loggingIn:
          loggingInView
        case .downloadingChunks(let numberReceived, let total):
          VStack {
            Text("Downloading chunks...")
            HStack {
              ProgressView(value: Double(numberReceived) / Double(total))
              Text("\(numberReceived) of \(total)")
            }
              .frame(maxWidth: 200)
            Button("Cancel", action: disconnect)
              .buttonStyle(SecondaryButtonStyle())
              .frame(width: 150)
          }
        case .playing:
          ZStack {
            gameView.opacity(cursorCaptured ? 1 : 0.2)

            overlayView
          }
        case .gpuFrameCaptureComplete(let file):
          VStack {
            Text("GPU frame capture complete")

            Group {
              #if os(macOS)
              Button("Show in finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file])
              }.buttonStyle(SecondaryButtonStyle())
              #elseif os(iOS)
              // TODO: Add a file sharing menu for iOS
              Text("I have no clue how to get hold of the file")
              #else
              #error("Unsupported platform, no file opening method")
              #endif

              Button("OK") {
                model.state.pop()
              }.buttonStyle(PrimaryButtonStyle())
            }.frame(width: 200)
          }
      }
    }
    .onDisappear {
      model.client.disconnect()
      model.renderCoordinator = RenderCoordinator(model.client)
    }
  }

  var connectingView: some View {
    VStack {
      Text("Establishing connection...")
      Button("Cancel", action: disconnect)
        .buttonStyle(SecondaryButtonStyle())
        .frame(width: 150)
    }
  }

  var loggingInView: some View {
    VStack {
      Text("Logging in...")
      Button("Cancel", action: disconnect)
        .buttonStyle(SecondaryButtonStyle())
        .frame(width: 150)
    }
  }

  var gameView: some View {
    ZStack {
      // Renderer
      MetalView(renderCoordinator: model.renderCoordinator)
        .onAppear {
          model.inputDelegate.bind($cursorCaptured.onChange { newValue in
            // When showing overlay make sure menu is the first view
            if newValue == false {
              model.overlayState.update(to: .menu)
            }
          })

          model.inputDelegate.captureCursor()
        }

      #if os(iOS)
      movementControls
      #endif
    }
  }

  var playerPositionString: String {
    func string(_ value: Double) -> String {
      String(format: "%.02f", value)
    }

    let position = playerPosition
    return "\(string(position.x)) \(string(position.y)) \(string(position.z))"
  }

  var playerChunkSectionString: String {
    let section = EntityPosition(playerPosition).chunkSection

    return "\(section.sectionX) \(section.sectionY) \(section.sectionZ)"
  }

  var playerPosition: SIMD3<Double> {
    var position = SIMD3<Double>(repeating: 0)
    model.client.game.accessPlayer { player in
      position = player.position.smoothVector
    }
    return position
  }

  var gamemode: Gamemode {
    var gamemode = Gamemode.survival
    model.client.game.accessPlayer { player in
      gamemode = player.gamemode.gamemode
    }
    return gamemode
  }

  var renderStats: RenderStatistics {
    model.renderCoordinator.statistics
  }

  var overlayView: some View {
    VStack {
      // In-game menu overlay
      if !cursorCaptured {
        switch model.overlayState.current {
          case .menu:
            VStack {
              Button("Back to game", action: model.closeMenu)
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(PrimaryButtonStyle())
              Button("Settings", action: { model.overlayState.update(to: .settings) })
                .buttonStyle(SecondaryButtonStyle())
              Button("Disconnect", action: disconnect)
                .buttonStyle(SecondaryButtonStyle())
            }
            .frame(width: 200)
          case .settings:
            SettingsView(isInGame: true, client: model.client, onDone: {
              model.overlayState.update(to: .menu)
            })
        }
      }
    }
  }

  #if os(iOS)
  var movementControls: some View {
    VStack {
      Spacer()
      HStack {
        HStack(alignment: .bottom) {
          movementControl("a", .strafeLeft)
          VStack {
            movementControl("w", .moveForward)
            movementControl("s", .moveBackward)
          }
          movementControl("d", .strafeRight)
        }
        Spacer()
        VStack {
          movementControl("*", .jump)
          movementControl("_", .sneak)
        }
      }
    }
  }

  func movementControl(_ label: String, _ input: Input) -> some View {
    return ZStack {
      Color.blue.frame(width: 50, height: 50)
      Text(label)
    }.onLongPressGesture(
      minimumDuration: 100000000000,
      maximumDistance: 50,
      perform: { return },
      onPressingChanged: { isPressing in
        if isPressing {
          model.client.press(input)
        } else {
          model.client.release(input)
        }
      }
    )
  }
  #endif

  func disconnect() {
    appState.update(to: .serverList)
  }
}
