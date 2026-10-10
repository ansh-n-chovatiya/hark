import CoreGraphics
import Foundation
import Testing
@testable import HarkCore

private let screen = CGRect(x: 0, y: 25, width: 1200, height: 900)
private let window = CGRect(x: 100, y: 100, width: 400, height: 300)

private func placed(_ place: WindowPlace, on screen: CGRect = screen) -> CGRect {
    WindowPlaces.frame(for: place, window: window, in: screen)
}

@Test func everyPlaceHasANameAModelCanSend() {
    #expect(WindowPlace.allCases.map(\.rawValue) == [
        "left", "right", "top", "bottom", "top_left", "top_right", "bottom_left", "bottom_right",
        "left_third", "middle_third", "right_third", "left_two_thirds", "right_two_thirds",
        "full", "centre", "next_screen",
    ])
}

@Test func halvesSplitTheScreen() {
    #expect(placed(.left) == CGRect(x: 0, y: 25, width: 600, height: 900))
    #expect(placed(.right) == CGRect(x: 600, y: 25, width: 600, height: 900))
    #expect(placed(.top) == CGRect(x: 0, y: 25, width: 1200, height: 450))
    #expect(placed(.bottom) == CGRect(x: 0, y: 475, width: 1200, height: 450))
}

@Test func quartersTakeACornerEach() {
    #expect(placed(.topLeft) == CGRect(x: 0, y: 25, width: 600, height: 450))
    #expect(placed(.topRight) == CGRect(x: 600, y: 25, width: 600, height: 450))
    #expect(placed(.bottomLeft) == CGRect(x: 0, y: 475, width: 600, height: 450))
    #expect(placed(.bottomRight) == CGRect(x: 600, y: 475, width: 600, height: 450))
}

@Test func thirdsAndTwoThirdsRunTheFullHeight() {
    #expect(placed(.leftThird) == CGRect(x: 0, y: 25, width: 400, height: 900))
    #expect(placed(.middleThird) == CGRect(x: 400, y: 25, width: 400, height: 900))
    #expect(placed(.rightThird) == CGRect(x: 800, y: 25, width: 400, height: 900))
    #expect(placed(.leftTwoThirds) == CGRect(x: 0, y: 25, width: 800, height: 900))
    #expect(placed(.rightTwoThirds) == CGRect(x: 400, y: 25, width: 800, height: 900))
}

@Test func thirdsOfAWidthThatDoesNotDivideStillMeet() {
    let odd = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let left = placed(.leftThird, on: odd)
    let middle = placed(.middleThird, on: odd)
    let right = placed(.rightThird, on: odd)
    #expect(left.minX == 0)
    #expect(left.maxX == middle.minX)
    #expect(middle.maxX == right.minX)
    #expect(right.maxX == 1000)
    #expect(placed(.leftTwoThirds, on: odd).maxX == middle.maxX)
    #expect(placed(.rightTwoThirds, on: odd).minX == middle.minX)
}

@Test func fullFillsTheUsableArea() {
    #expect(placed(.full) == screen)
}

@Test func centreKeepsTheSize() {
    #expect(placed(.centre) == CGRect(x: 400, y: 325, width: 400, height: 300))
}

@Test func centreShrinksAWindowLargerThanTheScreen() {
    let wide = CGRect(x: -50, y: 0, width: 2000, height: 300)
    #expect(WindowPlaces.frame(for: .centre, window: wide, in: screen) == CGRect(x: 0, y: 325, width: 1200, height: 300))

    let huge = CGRect(x: 0, y: 0, width: 2000, height: 1500)
    #expect(WindowPlaces.frame(for: .centre, window: huge, in: screen) == screen)
}

@Test func nextScreenAloneLeavesTheWindowWhereItIs() {
    #expect(placed(.nextScreen) == window)
}

@Test func placesFollowAScreenToTheLeftOfTheMainOne() {
    let leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    #expect(placed(.left, on: leftScreen) == CGRect(x: -1920, y: 0, width: 960, height: 1080))
    #expect(placed(.right, on: leftScreen) == CGRect(x: -960, y: 0, width: 960, height: 1080))
    #expect(placed(.bottomRight, on: leftScreen) == CGRect(x: -960, y: 540, width: 960, height: 540))
    #expect(placed(.middleThird, on: leftScreen) == CGRect(x: -1280, y: 0, width: 640, height: 1080))
    #expect(placed(.centre, on: leftScreen) == CGRect(x: -1160, y: 390, width: 400, height: 300))
}

@Test func placesFollowAScreenAboveTheMainOne() {
    let upperScreen = CGRect(x: 200, y: -1080, width: 1920, height: 1080)
    #expect(placed(.top, on: upperScreen) == CGRect(x: 200, y: -1080, width: 1920, height: 540))
    #expect(placed(.bottom, on: upperScreen) == CGRect(x: 200, y: -540, width: 1920, height: 540))
    #expect(placed(.topRight, on: upperScreen) == CGRect(x: 1160, y: -1080, width: 960, height: 540))
    #expect(placed(.full, on: upperScreen) == upperScreen)
}

@Test func aWindowBelongsToTheScreenItIsMostlyOn() {
    let screens = [CGRect(x: 0, y: 0, width: 1200, height: 900), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
    #expect(WindowPlaces.screenIndex(of: CGRect(x: 100, y: 100, width: 400, height: 300), in: screens) == 0)
    #expect(WindowPlaces.screenIndex(of: CGRect(x: -900, y: 100, width: 400, height: 300), in: screens) == 1)
    #expect(WindowPlaces.screenIndex(of: CGRect(x: -300, y: 100, width: 400, height: 300), in: screens) == 1)
    #expect(WindowPlaces.screenIndex(of: CGRect(x: -100, y: 100, width: 400, height: 300), in: screens) == 0)
}

@Test func aWindowOffEveryScreenBelongsToTheNearest() {
    let screens = [CGRect(x: 0, y: 0, width: 1200, height: 900), CGRect(x: 0, y: -1080, width: 1920, height: 1080)]
    #expect(WindowPlaces.screenIndex(of: CGRect(x: 3000, y: -900, width: 400, height: 300), in: screens) == 1)
    #expect(WindowPlaces.screenIndex(of: CGRect(x: 0, y: 2000, width: 400, height: 300), in: screens) == 0)
    #expect(WindowPlaces.screenIndex(of: window, in: []) == nil)
}

@Test func theNextScreenWrapsRound() {
    #expect(WindowPlaces.nextIndex(after: 0, count: 3) == 1)
    #expect(WindowPlaces.nextIndex(after: 2, count: 3) == 0)
    #expect(WindowPlaces.nextIndex(after: 0, count: 2) == 1)
    #expect(WindowPlaces.nextIndex(after: 1, count: 2) == 0)
}

@Test func oneScreenHasNoNextScreen() {
    #expect(WindowPlaces.nextIndex(after: 0, count: 1) == nil)
}

@Test func movingToAnotherScreenKeepsTheRelativePlace() {
    let main = CGRect(x: 0, y: 25, width: 1200, height: 900)
    let leftScreen = CGRect(x: -2400, y: 0, width: 2400, height: 1350)
    let rightHalf = CGRect(x: 600, y: 25, width: 600, height: 900)
    #expect(WindowPlaces.frame(of: rightHalf, movedFrom: main, to: leftScreen)
        == CGRect(x: -1200, y: 0, width: 1200, height: 1350))

    let back = WindowPlaces.frame(of: CGRect(x: -1200, y: 0, width: 1200, height: 1350), movedFrom: leftScreen, to: main)
    #expect(back == rightHalf)
}

@Test func movingToAnotherScreenKeepsTheWindowInsideIt() {
    let main = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let upperScreen = CGRect(x: 0, y: -600, width: 800, height: 600)
    let hangingOff = CGRect(x: 1000, y: 800, width: 600, height: 300)
    let moved = WindowPlaces.frame(of: hangingOff, movedFrom: main, to: upperScreen)
    #expect(moved == CGRect(x: 400, y: -200, width: 400, height: 200))
    #expect(upperScreen.contains(moved))
}

@Test func screenFramesAreFlippedToTopLeft() {
    // A main display 1200 x 900 with a 25 point menu bar and a 70 point Dock.
    #expect(WindowPlaces.topLeft(fromBottomLeft: CGRect(x: 0, y: 70, width: 1200, height: 805), mainHeight: 900)
        == CGRect(x: 0, y: 25, width: 1200, height: 805))
    // A display above the main one sits at positive y in AppKit and negative y from the top left.
    #expect(WindowPlaces.topLeft(fromBottomLeft: CGRect(x: 200, y: 900, width: 1920, height: 1080), mainHeight: 900)
        == CGRect(x: 200, y: -1080, width: 1920, height: 1080))
    // A display to the left, bottom edges level.
    #expect(WindowPlaces.topLeft(fromBottomLeft: CGRect(x: -1920, y: 0, width: 1920, height: 1080), mainHeight: 900)
        == CGRect(x: -1920, y: -180, width: 1920, height: 1080))
}

@Test func aSnappedSizeCountsAsClose() {
    let wanted = CGRect(x: 0, y: 25, width: 600, height: 900)
    #expect(WindowPlaces.isClose(CGRect(x: 0, y: 25, width: 595, height: 893), to: wanted, within: 8))
    #expect(!WindowPlaces.isClose(CGRect(x: 0, y: 25, width: 700, height: 900), to: wanted, within: 8))
    #expect(!WindowPlaces.isClose(CGRect(x: 40, y: 25, width: 600, height: 900), to: wanted, within: 8))
}
