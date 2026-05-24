import XCTest

final class PinesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.terminate()
        configureLaunch(resetStore: true)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    @MainActor
    func testLaunchNavigateTabsCreateChatAndTypeDraft() throws {
        launchAndWaitForMainUI()

        exerciseTopLevelPagesAndSafeActions()
        openTab("Chats")

        tapCreateChat()
        openFirstThreadIfComposerIsNotVisible()

        let input = app.descendants(matching: .any)["pines.chat.composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "New chat composer did not appear.")
        tapButtonOrSegment("Agent")
        tapButtonOrSegment("Chat")
        input.tap()
        input.typeText("UI test draft")

        let send = app.buttons["pines.chat.composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Composer send button did not appear.")
        XCTAssertTrue(send.isEnabled, "Composer send button should enable after typing a draft.")
    }

    @MainActor
    func testVaultSearchActionPresentsSearchField() throws {
        launchAndWaitForMainUI()
        openTab("Vault")

        let search = firstExisting([app.buttons["Search vault"], app.buttons["Search"]])
        XCTAssertNotNil(search, "Vault search action was missing.")
        search?.tap()
        XCTAssertTrue(
            waitForAny([app.searchFields.firstMatch, app.textFields["Search vault"]], timeout: 5),
            "Vault search did not present a search field."
        )
    }

    @MainActor
    func testContinuedChatStreamsAndPersistsAcrossRelaunch() throws {
        configureLaunch(scenario: "streaming", resetStore: true)
        launchAndWaitForMainUI()
        openTab("Chats")
        tapCreateChat()
        openFirstThreadIfComposerIsNotVisible()

        sendPrompt("First continued prompt")
        assertVisibleText(containing: "UI test response 1: First continued prompt", timeout: 20)
        XCTAssertTrue(waitForMessageCount(role: "user", atLeast: 1, timeout: 5), "First user message was not rendered.")
        XCTAssertTrue(waitForMessageCount(role: "assistant", atLeast: 1, timeout: 5), "First assistant message was not rendered.")

        sendPrompt("Second continued prompt")
        assertVisibleText(containing: "UI test response 1: Second continued prompt", timeout: 20)
        XCTAssertTrue(waitForMessageCount(role: "user", atLeast: 2, timeout: 5), "Continued user message was not rendered.")
        XCTAssertTrue(waitForMessageCount(role: "assistant", atLeast: 2, timeout: 5), "Continued assistant message was not rendered.")

        app.terminate()
        configureLaunch(scenario: "streaming", resetStore: false)
        launchAndWaitForMainUI()
        openTab("Chats")
        openFirstThreadIfComposerIsNotVisible()
        assertVisibleText(containing: "First continued prompt", timeout: 10)
        assertVisibleText(containing: "UI test response 1: Second continued prompt", timeout: 10)
    }

    @MainActor
    func testSlowGenerationCanBeStoppedAndComposerRecovers() throws {
        configureLaunch(scenario: "slow-streaming", resetStore: true)
        launchAndWaitForMainUI()
        openTab("Chats")
        tapCreateChat()
        openFirstThreadIfComposerIsNotVisible()

        sendPrompt("Stop this slow response", waitsForCompletion: false)
        let stop = app.buttons["pines.chat.composer.send"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "Stop control did not appear.")
        XCTAssertTrue(waitForSendButtonLabel("Stop", timeout: 5), "Send button should become Stop while generation is active.")
        stop.tap()

        XCTAssertTrue(waitForSendButtonLabel("Send", timeout: 10), "Composer did not return to Send after stopping generation.")
        let input = app.descendants(matching: .any)["pines.chat.composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Composer did not remain available after cancellation.")
        input.tap()
        input.typeText("Recovered draft")
        XCTAssertTrue(app.buttons["pines.chat.composer.send"].isEnabled, "Composer should accept a new draft after cancellation.")
    }

    @MainActor
    func testEmptyModelOutputSurfacesRecoverableFailure() throws {
        configureLaunch(scenario: "empty", resetStore: true)
        launchAndWaitForMainUI()
        openTab("Chats")
        tapCreateChat()
        openFirstThreadIfComposerIsNotVisible()

        sendPrompt("Return no output")
        assertVisibleText(containing: "returned a successful stream", timeout: 20)
        XCTAssertTrue(waitForSendButtonLabel("Send", timeout: 5), "Composer did not recover after empty output.")
    }

    @MainActor
    func testProviderFailureSurfacesErrorAndUnlocksComposer() throws {
        configureLaunch(scenario: "error", resetStore: true)
        launchAndWaitForMainUI()
        openTab("Chats")
        tapCreateChat()
        openFirstThreadIfComposerIsNotVisible()

        sendPrompt("Force provider failure")
        assertVisibleText(containing: "UI test provider failure.", timeout: 20)
        XCTAssertTrue(waitForSendButtonLabel("Send", timeout: 5), "Composer did not recover after provider failure.")
    }

    @MainActor
    func testSyntheticWatchdogFinishUnlocksComposer() throws {
        configureLaunch(scenario: "synthetic-watchdog-finish", resetStore: true)
        launchAndWaitForMainUI()
        openTab("Chats")
        tapCreateChat()
        openFirstThreadIfComposerIsNotVisible()

        sendPrompt("Hang local generation", waitsForCompletion: false)
        assertVisibleText(containing: "UI test local generation stalled before producing output.", timeout: 15)
        XCTAssertTrue(waitForSendButtonLabel("Send", timeout: 5), "Composer did not recover after local watchdog timeout.")
    }

    private func configureLaunch(scenario: String? = nil, resetStore: Bool) {
        app.launchArguments = ["--pines-ui-testing"]
        if resetStore {
            app.launchArguments.append("--pines-reset-ui-test-store")
        }
        var environment = [
            "PINES_UI_TESTING": "1",
            "PINES_UI_TEST_RESET_STORE": resetStore ? "1" : "0",
            "PINES_UI_TEST_DATABASE_FILE": "pines-ui-tests.sqlite",
            "PINES_UI_TEST_DATABASE_PLAINTEXT": "1",
        ]
        if let scenario {
            environment["PINES_UI_TEST_INFERENCE_SCENARIO"] = scenario
        }
        app.launchEnvironment = environment
    }

    @MainActor
    private func exerciseTopLevelPagesAndSafeActions() {
        openTab("Models")
        assertMenuCanOpen(buttonLabel: "All tasks", item: "All tasks")
        assertMenuCanOpen(buttonLabel: "Compatibility", item: "All compatibility")
        assertMenuCanOpen(buttonLabel: "State", item: "Any state")
        assertExists(app.buttons["Use as default model"], "Default model toolbar action was missing.")
        assertExists(app.buttons["Download model"], "Download model toolbar action was missing.")
        assertExists(app.buttons["Cancel model download"], "Cancel download toolbar action was missing.")
        assertExists(app.buttons["Delete model"], "Delete model toolbar action was missing.")

        openTab("Vault")
        assertExists(firstExisting([app.buttons["Import"], app.buttons["Search vault"]]), "Vault toolbar actions were missing.")
        assertExists(firstExisting([app.buttons["Search vault"], app.buttons["Search"]]), "Vault search action was missing.")

        openTab("Artifacts")
        assertExists(app.buttons["Refresh artifacts"], "Artifacts refresh action was missing.")
        switchArtifactsWorkspace(to: "Create")
        assertIdentifierVisible("pines.artifacts.media.prompt", "Create workspace prompt field was missing.")
        let createArtifact = app.buttons["pines.artifacts.media.create"]
        XCTAssertTrue(createArtifact.waitForExistence(timeout: 5), "Create artifact action was missing.")
        XCTAssertFalse(createArtifact.isEnabled, "Create artifact should stay disabled in UI test mode without a configured provider.")
        switchArtifactsWorkspace(to: "Research")
        assertIdentifierVisible("pines.artifacts.research.prompt", "Research workspace prompt field was missing.")
        let startResearch = app.buttons["pines.artifacts.research.start"]
        XCTAssertTrue(startResearch.waitForExistence(timeout: 5), "Start research action was missing.")
        XCTAssertFalse(startResearch.isEnabled, "Start research should stay disabled in UI test mode without a configured provider.")
        switchArtifactsWorkspace(to: "Library")
        assertIdentifierVisible("pines.artifacts.library.search", "Artifacts library search field was missing.")

        openTab("Settings")
        openSettingsSection("Design")
        assertStaticTextVisible("Appearance", "Design settings did not show Appearance.")
        tapButtonOrSegment("Dark")
        tapButtonOrSegment("System")
        openSettingsSection("Inference")
        assertStaticTextVisible("Execution", "Inference settings did not show Execution.")
        openSettingsSection("Privacy")
        assertStaticTextVisible("Storage and Sync", "Privacy settings did not show Storage and Sync.")
        openSettingsSection("Tools")
        assertStaticTextVisible("Agent Tool Keys", "Tools settings did not show Agent Tool Keys.")
        assertIdentifierVisible("pines.settings.mcp.name", "MCP display name field was missing.")
        assertIdentifierVisible("pines.settings.mcp.endpoint", "MCP endpoint field was missing.")
        assertStaticTextVisible("MCP Servers", "Tools settings did not show MCP Servers.")
        openSettingsSection("System")
        assertStaticTextVisible("Architecture Health", "System settings did not show Architecture Health.")
    }

    @MainActor
    private func launchAndWaitForMainUI() {
        app.launch()

        XCTAssertTrue(
            waitForAny([
                app.tabBars.firstMatch,
                app.staticTexts["Chats"],
                app.descendants(matching: .any)["pines.screen.chats"],
            ], timeout: 30),
            "Pines did not reach the main Chats UI."
        )
        XCTAssertFalse(app.staticTexts["Pines Locked"].exists, "UI test launch should not restore a locked app state.")
        let ready = app.descendants(matching: .any)["pines.ui-test.ready"]
        if !ready.waitForExistence(timeout: 30) {
            XCTFail("Pines did not finish UI test bootstrap with a ready local store.\n\n\(app.debugDescription)")
        }
    }

    @MainActor
    private func openTab(_ title: String) {
        closeTransientControlsIfNeeded()
        XCTAssertTrue(tapFirstExisting([
            app.tabBars.buttons[title],
            app.buttons[title],
        ], timeout: 10), "Could not tap \(title) tab.")

        var screenMarkers = [app.staticTexts[title]]
        if let identifier = screenIdentifier(for: title) {
            screenMarkers.insert(app.descendants(matching: .any)[identifier], at: 0)
        }
        XCTAssertTrue(waitForAny(screenMarkers, timeout: 10), "\(title) screen did not become visible.")
    }

    @MainActor
    private func tapCreateChat() {
        let create = app.buttons["pines.chat.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Create menu was not visible on Chats.")
        create.tap()

        let newChat = app.buttons["New chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 5), "New chat menu item was not visible.")
        newChat.tap()
    }

    @MainActor
    private func openFirstThreadIfComposerIsNotVisible() {
        let input = app.descendants(matching: .any)["pines.chat.composer.input"]
        if input.waitForExistence(timeout: 2) {
            return
        }

        let thread = app.descendants(matching: .any).matching(identifier: "pines.chat.thread.row").firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "New chat row was not created.")
        thread.tap()
    }

    @MainActor
    private func sendPrompt(_ text: String, waitsForCompletion: Bool = true) {
        selectChatRunModeIfVisible()
        let input = app.descendants(matching: .any)["pines.chat.composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Chat composer input did not appear.")
        input.tap()
        input.typeText(text)
        let send = app.buttons["pines.chat.composer.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send button did not appear.")
        XCTAssertTrue(send.isEnabled, "Send button was disabled after typing a prompt.")
        send.tap()
        if waitsForCompletion {
            XCTAssertTrue(waitForSendButtonLabel("Send", timeout: 20), "Generation did not finish.")
        }
    }

    @MainActor
    private func selectChatRunModeIfVisible() {
        dismissKeyboardIfNeeded()
        if app.buttons["Chat"].exists || app.segmentedControls.buttons["Chat"].exists {
            tapButtonOrSegment("Chat")
        }
    }

    @MainActor
    private func waitForSendButtonLabel(_ label: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let send = app.buttons["pines.chat.composer.send"]
        while Date() < deadline {
            if send.exists && send.label == label {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return send.exists && send.label == label
    }

    @MainActor
    private func assertVisibleText(containing text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch
        if element.waitForExistence(timeout: timeout) {
            return
        }
        app.swipeUp()
        if element.waitForExistence(timeout: 3) {
            return
        }
        XCTFail("Could not find visible text containing: \(text)\n\n\(app.debugDescription)")
    }

    @MainActor
    private func waitForMessageCount(role: String, atLeast minimum: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let query = app.descendants(matching: .any).matching(identifier: "pines.chat.message.\(role)")
        while Date() < deadline {
            if query.count >= minimum {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return query.count >= minimum
    }

    @MainActor
    private func switchArtifactsWorkspace(to title: String) {
        dismissKeyboardIfNeeded()
        let mode = app.buttons["pines.artifacts.workspace.mode"]
        if !mode.waitForExistence(timeout: 2) {
            let backToArtifacts = app.buttons["Back to artifacts"]
            if backToArtifacts.waitForExistence(timeout: 2) {
                backToArtifacts.tap()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(mode.waitForExistence(timeout: 10), "Artifacts workspace mode menu was not visible.")
        mode.tap()

        let item = app.buttons[title]
        if !item.waitForExistence(timeout: 2) {
            dismissKeyboardIfNeeded()
            mode.tap()
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Artifacts workspace mode \(title) was not visible.")
        item.tap()

        let visibleWorkspace: XCUIElement = switch title {
        case "Create":
            app.descendants(matching: .any)["pines.artifacts.media.prompt"]
        case "Research":
            app.descendants(matching: .any)["pines.artifacts.research.prompt"]
        case "Library":
            app.descendants(matching: .any)["pines.artifacts.library.search"]
        default:
            app.staticTexts[title]
        }
        XCTAssertTrue(visibleWorkspace.waitForExistence(timeout: 10), "Artifacts workspace \(title) did not become visible.")
    }

    @MainActor
    private func openSettingsSection(_ title: String) {
        returnToSettingsListIfNeeded()
        var row = firstExisting([
            app.descendants(matching: .any)["pines.settings.section.\(title.uiTestIdentifierComponent)"],
            app.staticTexts[title],
            app.buttons[title],
        ])
        if row == nil {
            app.swipeUp()
            row = firstExisting([
                app.descendants(matching: .any)["pines.settings.section.\(title.uiTestIdentifierComponent)"],
                app.staticTexts[title],
                app.buttons[title],
            ])
        }
        XCTAssertNotNil(row, "Could not find \(title) settings section.")
        row?.tap()
    }

    @MainActor
    private func returnToSettingsListIfNeeded() {
        let back = app.navigationBars.buttons["Settings"].firstMatch
        guard back.exists else { return }
        back.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5), "Settings list did not become visible.")
    }

    @MainActor
    private func assertMenuCanOpen(buttonLabel: String, item: String) {
        let button = app.buttons[buttonLabel].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Menu button \(button) was not visible.")
        button.tap()
        let menuItem = app.buttons[item].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "Menu item \(item) was not visible.")
        menuItem.tap()
    }

    @MainActor
    private func assertExists(_ element: XCUIElement?, _ message: String) {
        guard let element else {
            XCTFail(message)
            return
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10), message)
    }

    @MainActor
    private func assertStaticTextVisible(_ title: String, _ message: String) {
        let text = app.staticTexts[title].firstMatch
        if text.waitForExistence(timeout: 5) {
            return
        }

        app.swipeUp()
        XCTAssertTrue(text.waitForExistence(timeout: 5), message)
    }

    @MainActor
    private func typeText(intoIdentifier identifier: String, text: String) {
        let field = app.descendants(matching: .any)[identifier]
        if !field.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Text field \(identifier) was not visible.")
        field.tap()
        field.typeText(text)
        dismissKeyboardIfNeeded()
    }

    @MainActor
    private func assertIdentifierVisible(_ identifier: String, _ message: String) {
        let element = app.descendants(matching: .any)[identifier]
        if element.waitForExistence(timeout: 5) {
            return
        }

        app.swipeUp()
        XCTAssertTrue(element.waitForExistence(timeout: 5), message)
    }

    @MainActor
    private func tapButtonOrSegment(_ title: String) {
        dismissKeyboardIfNeeded()
        XCTAssertTrue(tapFirstExisting([
            app.buttons[title],
            app.segmentedControls.buttons[title],
        ], timeout: 10), "Could not tap \(title) control.")
    }

    @MainActor
    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    }

    @MainActor
    private func closeTransientControlsIfNeeded() {
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        }
        dismissKeyboardIfNeeded()
    }

    @MainActor
    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return elements.contains(where: { $0.exists })
    }

    @MainActor
    private func firstExisting(_ elements: [XCUIElement]) -> XCUIElement? {
        elements.first { $0.exists }
    }

    private func screenIdentifier(for title: String) -> String? {
        switch title {
        case "Chats": "pines.screen.chats"
        case "Models": "pines.screen.models"
        case "Vault": "pines.screen.vault"
        case "Artifacts": "pines.screen.artifacts"
        case "Settings": "pines.screen.settings"
        default: nil
        }
    }

    @MainActor
    private func tapFirstExisting(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for element in elements where element.exists && element.isHittable {
                element.tap()
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}

private extension String {
    var uiTestIdentifierComponent: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
