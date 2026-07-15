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
    func testSettingsInformationArchitectureAndFocusedPages() throws {
        launchAndWaitForMainUI()
        openTab("Settings")

        let destinations = [
            ("Appearance", "Color & appearance"),
            ("AI & Models", "Default routing"),
            ("Cloud & Providers", "My providers"),
            ("Privacy & Data", "Security"),
            ("Tools & Integrations", "Built-in tools"),
            ("Help & Diagnostics", "Health"),
        ]

        for (destination, expectedGroup) in destinations {
            openSettingsSection(destination)
            assertStaticTextVisible(expectedGroup, "\(destination) did not show its focused settings content.")
            captureScreenshot(named: "Settings - \(destination)")
        }
    }

    @MainActor
    func testAccessibilityTextSizeKeepsPrimarySurfacesReachable() throws {
        configureLaunch(resetStore: true)
        app.launchEnvironment["PINES_UI_TEST_ACCESSIBILITY_TEXT"] = "1"
        app.launchEnvironment["PINES_UI_TEST_DARK_APPEARANCE"] = "1"
        app.launchEnvironment["PINES_UI_TEST_ARTIFACTS_FIXTURE"] = "1"
        launchAndWaitForMainUI()

        openTab("Models")
        assertMenuCanOpen(buttonLabel: "All tasks", item: "All tasks")

        openTab("Vault")
        assertExists(app.buttons["Vault settings"], "Vault settings should remain reachable at accessibility text sizes.")

        openTab("Artifacts")
        assertIdentifierVisible("pines.artifacts.library", "Artifact library should remain reachable at accessibility text sizes.")
        assertVisibleText(containing: "Architectural study of a glass cabin", timeout: 10)
        captureScreenshot(named: "Artifacts - Accessibility XXXL Dark")
        openArtifactsDestination(menuItem: "Image", destinationIdentifier: "pines.artifacts.image-studio.canvas")
        captureScreenshot(named: "Artifacts - Image Accessibility XXXL Dark")
        returnToArtifactsLibrary()
        openArtifactsDestination(menuItem: "Deep Research", destinationIdentifier: "pines.artifacts.research.prompt")
        captureScreenshot(named: "Artifacts - Research Accessibility XXXL Dark")
        returnToArtifactsLibrary()

        openTab("Chats")
        tapCreateChat()
        openFirstThreadIfComposerIsNotVisible()
        assertIdentifierVisible("pines.chat.composer.input", "Chat composer should remain reachable at accessibility text sizes.")
        assertIdentifierVisible("pines.chat.composer.run-mode", "Run mode should remain reachable at accessibility text sizes.")
        assertIdentifierVisible("pines.chat.composer.send", "Send should remain reachable at accessibility text sizes.")
    }

    @MainActor
    func testArtifactsLibraryAndFocusedDestinations() throws {
        configureLaunch(resetStore: true)
        app.launchEnvironment["PINES_UI_TEST_ARTIFACTS_FIXTURE"] = "1"
        launchAndWaitForMainUI()

        openTab("Artifacts")
        assertIdentifierVisible("pines.artifacts.library", "The populated Artifact library was missing.")
        assertVisibleText(containing: "Architectural study of a glass cabin", timeout: 10)
        assertVisibleText(containing: "Low-impact woodland materials", timeout: 10)
        captureScreenshot(named: "Artifacts - Library")

        openArtifactDetail(title: "Architectural study of a glass cabin")
        captureScreenshot(named: "Artifacts - Detail")
        closeArtifactDetail()

        setArtifactScope("Images")
        assertVisibleText(containing: "Architectural study of a glass cabin", timeout: 10)
        captureScreenshot(named: "Artifacts - Images")
        setArtifactScope("All")

        openArtifactsDestination(menuItem: "Image", destinationIdentifier: "pines.artifacts.image-studio.canvas")
        assertVisibleText(containing: "OpenAI Studio", timeout: 10)
        assertIdentifierVisible("pines.artifacts.image-studio.canvas", "The canvas-first Image Studio did not appear.")
        assertIdentifierVisible("pines.artifacts.create.prompt", "The Image Studio floating prompt did not appear.")
        captureScreenshot(named: "Artifacts - Create")

        let imageSettings = app.buttons["pines.artifacts.image-studio.configuration"]
        XCTAssertTrue(imageSettings.waitForExistence(timeout: 5), "Image Studio settings were not reachable from the engine row.")
        imageSettings.tap()
        assertVisibleText(containing: "Shape the output", timeout: 5)
        captureScreenshot(named: "Artifacts - Image Settings")
        XCTAssertTrue(tapFirstExisting([app.buttons["Done"]], timeout: 5), "Image Studio settings had no Done action.")
        returnToArtifactsLibrary()

        openArtifactsDestination(menuItem: "Video", destinationIdentifier: "pines.artifacts.create.prompt")
        let videoSettings = app.buttons["pines.artifacts.create.configuration"]
        XCTAssertTrue(videoSettings.waitForExistence(timeout: 5), "Video settings were not reachable.")
        videoSettings.tap()
        assertVisibleText(containing: "Configure the render", timeout: 5)
        captureScreenshot(named: "Artifacts - Video Settings")
        XCTAssertTrue(tapFirstExisting([app.buttons["Done"]], timeout: 5), "Video settings had no Done action.")
        returnToArtifactsLibrary()

        openArtifactsDestination(menuItem: "Speech", destinationIdentifier: "pines.artifacts.create.prompt")
        let speechSettings = app.buttons["pines.artifacts.create.configuration"]
        XCTAssertTrue(speechSettings.waitForExistence(timeout: 5), "Speech settings were not reachable.")
        speechSettings.tap()
        assertVisibleText(containing: "Shape the voice", timeout: 5)
        captureScreenshot(named: "Artifacts - Speech Settings")
        XCTAssertTrue(tapFirstExisting([app.buttons["Done"]], timeout: 5), "Speech settings had no Done action.")
        returnToArtifactsLibrary()

        openArtifactsDestination(menuItem: "Deep Research", destinationIdentifier: "pines.artifacts.research.prompt")
        assertVisibleText(containing: "Turn a question into a sourced brief", timeout: 10)
        assertIdentifierVisible("pines.artifacts.research.prompt", "The floating Research prompt did not appear.")
        captureScreenshot(named: "Artifacts - Deep Research")

        let researchSettings = app.buttons["pines.artifacts.research.settings"]
        XCTAssertTrue(researchSettings.waitForExistence(timeout: 5), "Research setup was not reachable.")
        researchSettings.tap()
        assertVisibleText(containing: "Define the research brief", timeout: 5)
        captureScreenshot(named: "Artifacts - Research Settings")
        XCTAssertTrue(tapFirstExisting([app.buttons["Done"]], timeout: 5), "Research settings had no Done action.")

        let starter = app.buttons["Compare options"]
        XCTAssertTrue(starter.waitForExistence(timeout: 5), "Research starter prompts were missing.")
        starter.tap()
        let researchSend = app.buttons["pines.artifacts.research.send"]
        XCTAssertTrue(researchSend.waitForExistence(timeout: 5), "Research send action was missing.")
        researchSend.tap()
        assertVisibleText(containing: "Sharpen the question", timeout: 5)
        captureScreenshot(named: "Artifacts - Shape Research Brief")
        XCTAssertTrue(tapFirstExisting([app.buttons["Cancel"]], timeout: 5), "Research clarification had no Cancel action.")
        XCTAssertTrue(
            app.descendants(matching: .any)["pines.artifacts.research.prompt"].waitForExistence(timeout: 5),
            "Cancelling clarification did not return to the Research composer."
        )
        returnToArtifactsLibrary()

        openRunningResearch()
        assertVisibleText(containing: "Researching", timeout: 10)
        captureScreenshot(named: "Artifacts - Active Research")
    }

    @MainActor
    func testArtifactsLibraryRendersAcrossEveryPinesThemeInLightAndDark() throws {
        configureLaunch(resetStore: true)
        app.launchEnvironment["PINES_UI_TEST_ARTIFACTS_FIXTURE"] = "1"
        launchAndWaitForMainUI()

        let templates = ["evergreen", "graphite", "aurora", "paper", "slate", "porcelain", "sunset", "obsidian"]
        for appearance in ["Light", "Dark"] {
            openTab("Settings")
            openSettingsSection("Appearance")
            for _ in 0..<4 { app.swipeDown() }
            selectInterfaceMode(appearance)

            for template in templates {
                selectThemeTemplate(template)
                openTab("Artifacts")
                assertIdentifierVisible(
                    "pines.artifacts.library",
                    "The Artifact library did not render for \(template) in \(appearance.lowercased()) mode."
                )
                assertVisibleText(containing: "Architectural study of a glass cabin", timeout: 10)
                captureScreenshot(named: "Artifacts Theme - \(template.capitalized) \(appearance)")

                openTab("Settings")
                openSettingsSection("Appearance")
            }
        }
    }

    @MainActor
    func testArtifactsProviderSetupOpensCloudProviderSettings() throws {
        launchAndWaitForMainUI()

        openTab("Artifacts")
        openArtifactsDestination(menuItem: "Image", destinationIdentifier: "pines.artifacts.provider-setup")
        let setup = app.buttons["Provider setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10), "Artifact creation did not offer provider setup.")
        setup.tap()

        assertIdentifierVisible(
            "pines.settings.detail.cloudProviders",
            "Artifact provider setup did not hand off directly to Cloud & Providers."
        )
    }

    @MainActor
    func testChatDeletionRequiresExplicitConfirmation() throws {
        launchAndWaitForMainUI()
        openTab("Chats")
        tapCreateChat()
        openFirstThreadIfComposerIsNotVisible()

        let back = app.navigationBars.buttons["Chats"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Chat list back button was missing.")
        back.tap()

        let thread = app.descendants(matching: .any).matching(identifier: "pines.chat.thread.row").firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Created chat row was missing.")
        thread.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Delete swipe action was missing.")
        delete.tap()

        XCTAssertTrue(app.staticTexts["Delete this chat?"].waitForExistence(timeout: 5), "Chat deletion did not request confirmation.")
        XCTAssertTrue(app.buttons["Delete chat"].exists, "Confirmed destructive action was missing.")
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
        assertExists(
            firstExisting([app.staticTexts["Installed models"], app.staticTexts["MLX Hub results"]]),
            "The model library result summary was missing."
        )

        openTab("Vault")
        assertExists(firstExisting([app.buttons["Import"], app.buttons["Search vault"]]), "Vault toolbar actions were missing.")
        assertExists(firstExisting([app.buttons["Search vault"], app.buttons["Search"]]), "Vault search action was missing.")
        assertExists(app.buttons["Vault settings"], "Vault settings action was missing.")

        openTab("Artifacts")
        assertIdentifierVisible("pines.artifacts.library", "The artifact library was missing.")
        openArtifactsDestination(menuItem: "Image", destinationIdentifier: "pines.artifacts.image-studio.canvas")
        returnToArtifactsLibrary()
        openArtifactsDestination(menuItem: "Deep Research", destinationIdentifier: "pines.artifacts.research.prompt")
        returnToArtifactsLibrary()

        openTab("Settings")
        openSettingsSection("Appearance")
        assertStaticTextVisible("Color & appearance", "Appearance settings did not show color controls.")
        selectInterfaceMode("Dark")
        selectInterfaceMode("System")
        openSettingsSection("AI & Models")
        assertStaticTextVisible("Default routing", "AI & Models settings did not show routing controls.")
        openSettingsSection("Cloud & Providers")
        assertStaticTextVisible("My providers", "Cloud & Providers settings did not show provider controls.")
        openSettingsSection("Privacy & Data")
        assertStaticTextVisible("Security", "Privacy & Data settings did not show security controls.")
        openSettingsSection("Tools & Integrations")
        assertStaticTextVisible("Built-in tools", "Tools & Integrations did not show built-in tools.")
        assertStaticTextVisible("MCP servers", "Tools & Integrations did not show MCP servers.")
        openSettingsSection("Help & Diagnostics")
        assertStaticTextVisible("Health", "Help & Diagnostics did not show service health.")
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
        if let identifier = screenIdentifier(for: title),
           app.descendants(matching: .any)[identifier].exists {
            return
        }

        let labeledButtons = app.buttons
            .matching(NSPredicate(format: "label == %@", title))
            .allElementsBoundByIndex
        XCTAssertTrue(tapFirstExisting([
            app.tabBars.buttons[title],
            app.buttons[title],
        ] + labeledButtons, timeout: 10) || tapTabBarSlot(title), "Could not tap \(title) tab.")

        var screenMarkers = [app.staticTexts[title], app.navigationBars[title]]
        if let identifier = screenIdentifier(for: title) {
            screenMarkers.insert(app.descendants(matching: .any)[identifier], at: 0)
        }
        if !waitForAny(screenMarkers, timeout: 10) {
            closeTransientControlsIfNeeded()
            _ = tapTabBarSlot(title)
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
    private func openArtifactsDestination(menuItem: String, destinationIdentifier: String) {
        dismissKeyboardIfNeeded()
        let newArtifact = app.buttons["pines.artifacts.new"]
        XCTAssertTrue(newArtifact.waitForExistence(timeout: 10), "Artifact New command was not visible.")
        newArtifact.tap()

        let menuID: String
        switch menuItem {
        case "Image": menuID = "image"
        case "Video": menuID = "video"
        case "Speech": menuID = "speech"
        case "Deep Research", "Research": menuID = "research"
        default:
            XCTFail("Unknown Artifact destination: \(menuItem)")
            return
        }

        let item = firstExisting([
            app.buttons["pines.artifacts.new.\(menuID)"],
            app.buttons[menuID == "research" ? "Research" : menuItem],
        ])
        XCTAssertNotNil(item, "Artifact action \(menuItem) was not visible.")
        item?.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[destinationIdentifier].waitForExistence(timeout: 10),
            "Artifact destination \(menuItem) did not become visible."
        )
    }

    @MainActor
    private func returnToArtifactsLibrary() {
        let close = app.buttons["pines.artifacts.sheet.close"]
        if close.waitForExistence(timeout: 5) {
            close.tap()
            assertIdentifierVisible("pines.artifacts.library", "Artifact library did not reappear.")
            return
        }

        let library = app.descendants(matching: .any)["pines.artifacts.library"]
        if library.exists, library.isHittable {
            return
        }

        dismissKeyboardIfNeeded()
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Artifact destination had no close action.")
        close.tap()
        assertIdentifierVisible("pines.artifacts.library", "Artifact library did not reappear.")
    }

    @MainActor
    private func openArtifactDetail(title: String) {
        let opener = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        XCTAssertTrue(opener.waitForExistence(timeout: 10), "Artifact \(title) was not visible.")
        opener.tap()

        let detail = app.descendants(matching: .any)["pines.artifacts.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "Artifact details did not open.")

        XCTAssertTrue(
            app.buttons["pines.artifacts.sheet.close"].waitForExistence(timeout: 5),
            "Artifact Quick Look should be a dismissible sheet on every device."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["pines.artifacts.inspector"].exists,
            "Artifact Quick Look must not create an iPad side rail."
        )
    }

    @MainActor
    private func closeArtifactDetail() {
        let closed = tapFirstExisting([app.buttons["pines.artifacts.sheet.close"]], timeout: 10)
        XCTAssertTrue(closed, "Artifact details had no close action.")
        assertIdentifierVisible("pines.artifacts.library", "Artifact library did not remain visible after closing details.")
    }

    @MainActor
    private func setArtifactScope(_ title: String) {
        let filters = app.buttons["pines.artifacts.filter"]
        XCTAssertTrue(filters.waitForExistence(timeout: 10), "Artifact filter control was missing.")
        filters.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Artifact scope \(title) was missing.")
        option.tap()
    }

    @MainActor
    private func openRunningResearch() {
        let activity = app.buttons["pines.artifacts.activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 10), "The running-work summary was missing.")
        activity.tap()

        let run = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Low-impact woodland materials")
        ).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 5), "The active research thread was missing from running work.")
        run.tap()
        assertIdentifierVisible("pines.artifacts.research.follow-up", "The active research thread did not open.")
    }

    @MainActor
    private func captureScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openSettingsSection(_ title: String) {
        returnToSettingsListIfNeeded()
        let destinationID = settingsDestinationID(for: title)
        var row = firstExisting([
            app.descendants(matching: .any)["pines.settings.section.\(destinationID)"],
            app.staticTexts[title],
            app.buttons[title],
        ])
        if row == nil {
            app.swipeUp()
            row = firstExisting([
                app.descendants(matching: .any)["pines.settings.section.\(destinationID)"],
                app.staticTexts[title],
                app.buttons[title],
            ])
        }
        XCTAssertNotNil(row, "Could not find \(title) settings section.")
        row?.tap()
    }

    private func settingsDestinationID(for title: String) -> String {
        switch title {
        case "Appearance": "appearance"
        case "AI & Models": "aiModels"
        case "Cloud & Providers": "cloudProviders"
        case "Privacy & Data": "privacyData"
        case "Tools & Integrations": "toolsIntegrations"
        case "Help & Diagnostics": "diagnostics"
        default: title.uiTestIdentifierComponent
        }
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
    private func selectInterfaceMode(_ title: String) {
        let picker = app.descendants(matching: .any)["pines.settings.interface-mode"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Interface appearance control was missing.")
        picker.tap()

        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Interface appearance option \(title) was missing.")
        option.tap()
    }

    @MainActor
    private func selectThemeTemplate(_ rawValue: String) {
        let identifier = "pines.settings.theme.\(rawValue)"
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Theme control \(rawValue) was missing.")

        var attempts = 0
        while !button.isHittable, attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(button.isHittable, "Theme control \(rawValue) could not be reached.")
        button.tap()
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

    @MainActor
    private func tapTabBarSlot(_ title: String) -> Bool {
        guard let index = tabIndex(for: title) else { return false }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 2) else { return false }

        let button = tabBar.buttons.element(boundBy: index)
        if button.exists && button.isHittable {
            button.tap()
            return true
        }

        let tabCount = CGFloat(PinesUITests.tabTitles.count)
        let normalizedX = (CGFloat(index) + 0.5) / tabCount
        tabBar.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5)).tap()
        return true
    }

    private func tabIndex(for title: String) -> Int? {
        Self.tabTitles.firstIndex(of: title)
    }

    private static let tabTitles = ["Chats", "Models", "Vault", "Artifacts", "Settings"]
}

private extension String {
    var uiTestIdentifierComponent: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
