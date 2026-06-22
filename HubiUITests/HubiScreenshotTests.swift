import XCTest

@MainActor
final class HubiScreenshotTests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testTakeScreenshots() throws {
        sleep(3)
        takeScreenshot(name: "01-home")
        
        let firstAgent = app.cells.firstMatch
        if firstAgent.waitForExistence(timeout: 5) {
            firstAgent.tap()
            sleep(2)
            takeScreenshot(name: "02-chat")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        
        let agentTab = app.tabBars.buttons.element(boundBy: 1)
        if agentTab.exists {
            agentTab.tap()
            sleep(1)
            takeScreenshot(name: "03-agents")
        }
        
        let searchTab = app.tabBars.buttons.element(boundBy: 2)
        if searchTab.exists {
            searchTab.tap()
            sleep(1)
            takeScreenshot(name: "04-search")
        }
        
        let settingsTab = app.tabBars.buttons.element(boundBy: 3)
        if settingsTab.exists {
            settingsTab.tap()
            sleep(1)
            takeScreenshot(name: "05-settings")
        }
        
        let chatTab = app.tabBars.buttons.element(boundBy: 0)
        if chatTab.exists {
            chatTab.tap()
            sleep(1)
        }
        
        let paywallButton = app.buttons["会员"].exists ? app.buttons["会员"] : 
                           app.buttons["Pro"].exists ? app.buttons["Pro"] :
                           app.buttons["升级"].exists ? app.buttons["升级"] : nil
        
        if let btn = paywallButton, btn.waitForExistence(timeout: 3) {
            btn.tap()
            sleep(2)
            takeScreenshot(name: "06-paywall")
        }
    }
    
    func takeScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
