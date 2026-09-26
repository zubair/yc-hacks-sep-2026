import Foundation
import Testing
@testable import GonioCore

@Suite("Recovery curve")
struct RecoveryTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Noon on 26 Sep 2026, UTC.
    let now = Date(timeIntervalSince1970: 1_790_424_000)

    @Test func dailyBestKeepsTheHighestReadingPerDay() {
        let surgery = calendar.date(byAdding: .day, value: -5, to: calendar.startOfDay(for: now))!
        let patient = Patient(id: "p", name: "P", joint: "knee", surgeryDate: surgery, goal: 110, readings: [
            Reading(date: now, flexion: 98),
            Reading(date: now, flexion: 104),
            Reading(date: now.addingTimeInterval(-86_400), flexion: 97),
        ])
        let bests = Recovery.dailyBests(for: patient, calendar: calendar)
        #expect(bests == [DailyBest(postOpDay: 4, flexion: 97), DailyBest(postOpDay: 5, flexion: 104)])
    }

    @Test func slopeOfAStraightLine() throws {
        let bests = (0..<7).map { DailyBest(postOpDay: 10 + $0, flexion: 80 + 2 * Double($0)) }
        let slope = try #require(Recovery.slope(of: bests))
        #expect(abs(slope - 2) < 1e-9)
    }

    @Test func slopeUsesOnlyTheRecentWindow() throws {
        // Fast early gains, then flat for the last seven readings.
        let early = (0..<5).map { DailyBest(postOpDay: $0, flexion: 60 + 10 * Double($0)) }
        let late = (5..<12).map { DailyBest(postOpDay: $0, flexion: 100) }
        let slope = try #require(Recovery.slope(of: early + late))
        #expect(abs(slope) < 1e-9)
    }

    @Test func needsThreePointsForATrend() {
        #expect(Recovery.slope(of: [DailyBest(postOpDay: 1, flexion: 60), DailyBest(postOpDay: 2, flexion: 62)]) == nil)
    }

    @Test func seededPatientIsOnTrackWithNoReadingToday() throws {
        let alex = DemoData.alex(now: now, calendar: calendar)
        let summary = Recovery.summary(for: alex, now: now, calendar: calendar)
        #expect(summary.postOpDay == 24)
        #expect(summary.today == nil)
        #expect(summary.latest == DailyBest(postOpDay: 23, flexion: 101))
        #expect(!summary.isPlateau)
        let slope = try #require(summary.slope)
        #expect(slope > 1)
        #expect(summary.daysToGoal != nil)
    }

    @Test func liveCaptureBecomesToday() {
        var alex = DemoData.alex(now: now, calendar: calendar)
        alex.readings.append(Reading(date: now, flexion: 104))
        let summary = Recovery.summary(for: alex, now: now, calendar: calendar)
        #expect(summary.today == 104)
        #expect(summary.remaining == 6)
    }

    @Test func seededClinicPatientIsFlaggedAsPlateau() {
        let sam = DemoData.sam(now: now, calendar: calendar)
        let summary = Recovery.summary(for: sam, now: now, calendar: calendar)
        #expect(summary.isPlateau)
        #expect(summary.daysToGoal == nil)
    }

    @Test func goalReachedMeansNothingRemaining() {
        var alex = DemoData.alex(now: now, calendar: calendar)
        alex.readings.append(Reading(date: now, flexion: 112))
        let summary = Recovery.summary(for: alex, now: now, calendar: calendar)
        #expect(summary.remaining == 0)
        #expect(!summary.isPlateau)
        #expect(summary.daysToGoal == 0)
    }

    @Test func reportCarriesTheNumbersAPTNeeds() {
        var alex = DemoData.alex(now: now, calendar: calendar)
        alex.readings.append(Reading(date: now, flexion: 104))
        let calibration = Calibration(offset: -2, calibratedAt: now)
        let report = PTReport.text(for: alex, calibration: calibration, now: now, calendar: calendar)
        #expect(report.contains("Post-op day 24"))
        #expect(report.contains("Today's best flexion: 104° (goal 110°, 6° to go)"))
        #expect(report.contains("Day 23: 101°"))
        #expect(report.contains("offset -2.0°"))
    }

    @Test func reportSaysSoWhenThereIsNoReadingToday() {
        let alex = DemoData.alex(now: now, calendar: calendar)
        let report = PTReport.text(for: alex, calibration: .uncalibrated, now: now, calendar: calendar)
        #expect(report.contains("No reading yet today. Last: 101° on day 23"))
        #expect(report.contains("Not calibrated."))
    }
}

@Suite("Persistence")
struct PersistenceTests {
    @Test func roundTripsTheWholeState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let store = StateStore(url: url)
        #expect(store.load() == nil)

        var state = DemoData.state(now: .now)
        state.calibration = Calibration(offset: 1.5, calibratedAt: Date(timeIntervalSinceReferenceDate: 0))
        try store.save(state)
        #expect(store.load() == state)
    }
}
