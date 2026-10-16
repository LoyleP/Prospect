// ProspectTests/ViewModelTests.swift
import XCTest
@testable import Prospect

@MainActor
final class ProspectFormViewModelTests: XCTestCase {
    private let programs = [
        Program(id: UUID(), name: "Informatique", color: "#3366E6", sortOrder: 0),
        Program(id: UUID(), name: "Design", color: "#9440D9", sortOrder: 1),
    ]

    private func filled(_ vm: ProspectFormViewModel) {
        vm.prenom = " Léa "
        vm.nom = "Durand"
        vm.email = "lea@exemple.fr"
        vm.telephone = "+33 6 12 34 56 78"
        if vm.programId == nil { vm.programId = programs.first?.id }
    }

    func testCreateModeStartsWithoutProgramAndRequiresOne() {
        let session = TestData.session()
        UserDefaults.standard.removeObject(forKey: "lastProgram.\(session.id.uuidString)")
        let vm = ProspectFormViewModel(mode: .create(session: session), programs: programs, service: MockProspectService())
        XCTAssertNil(vm.programId, "no silent default: a wrong programme would skew the stats")
        XCTAssertEqual(vm.statut, .curieux)
        vm.prenom = "Léa"; vm.nom = "Durand"; vm.email = "lea@exemple.fr"; vm.telephone = "0612345678"
        XCTAssertTrue(vm.needsProgram)
        XCTAssertFalse(vm.isValid)
        vm.programId = programs[1].id
        XCTAssertTrue(vm.isValid)
    }

    func testCreateModeRemembersLastProgramUsed() async {
        let session = TestData.session()
        UserDefaults.standard.removeObject(forKey: "lastProgram.\(session.id.uuidString)")
        let first = ProspectFormViewModel(mode: .create(session: session), programs: programs, service: MockProspectService())
        filled(first); first.programId = programs[1].id
        _ = await first.save()
        let next = ProspectFormViewModel(mode: .create(session: session), programs: programs, service: MockProspectService())
        XCTAssertEqual(next.programId, programs[1].id)
    }

    func testCreateModeWithoutProgramsHasNoProgram() {
        let vm = ProspectFormViewModel(mode: .create(session: TestData.session()), programs: [], service: MockProspectService())
        XCTAssertNil(vm.programId)
    }

    func testValidation() {
        let vm = ProspectFormViewModel(mode: .create(session: TestData.session()), programs: programs, service: MockProspectService())
        filled(vm)
        XCTAssertTrue(vm.isValid)
        vm.email = "pas-un-email"
        XCTAssertFalse(vm.isValid)
        vm.email = "lea@exemple.fr"
        vm.telephone = "12-34"
        XCTAssertFalse(vm.isValid, "fewer than 6 digits")
        vm.telephone = "06 abc 12345"
        XCTAssertFalse(vm.isValid, "letters")
    }

    func testEditModePopulatesFields() {
        let prospect = TestData.prospect(programId: programs[1].id, statut: .interesse)
        let vm = ProspectFormViewModel(mode: .edit(prospect), programs: programs, service: MockProspectService())
        XCTAssertEqual(vm.prenom, "Léa")
        XCTAssertEqual(vm.programId, programs[1].id)
        XCTAssertEqual(vm.statut, .interesse)
    }

    func testSaveCreatesWithTrimmedInput() async {
        let service = MockProspectService()
        let session = TestData.session()
        let vm = ProspectFormViewModel(mode: .create(session: session), programs: programs, service: service)
        filled(vm)
        vm.notes = "   "

        let saved = await vm.save()

        XCTAssertNotNil(saved)
        XCTAssertEqual(service.createdInputs.count, 1)
        XCTAssertEqual(service.createdInputs.first?.sessionId, session.id)
        XCTAssertEqual(service.createdInputs.first?.input.prenom, "Léa")
        XCTAssertNil(service.createdInputs.first?.input.notes, "blank notes are sent as null")
    }

    func testSaveSurfacesErrors() async {
        let service = MockProspectService()
        service.errorToThrow = ServiceError.notAllowed
        let vm = ProspectFormViewModel(mode: .create(session: TestData.session()), programs: programs, service: service)
        filled(vm)
        let saved = await vm.save()
        XCTAssertNil(saved)
        XCTAssertNotNil(vm.errorMessage)
    }
}

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testStatsByProgramStatusAndAdvisor() async {
        let info = Program(id: UUID(), name: "Informatique", color: "#3366E6", sortOrder: 0)
        let design = Program(id: UUID(), name: "Design", color: "#9440D9", sortOrder: 1)
        let session = TestData.session(preRegistered: 10)
        let service = MockProspectService()
        service.summaries = [SessionSummary(session: session, prospectCount: 3)]
        service.prospects = [
            TestData.prospect(sessionId: session.id, programId: info.id, statut: .rdvInfo),
            TestData.prospect(sessionId: session.id, programId: info.id, statut: .rdvAdmission),
            TestData.prospect(sessionId: session.id, programId: design.id, statut: .curieux, agent: "Hugo"),
        ]

        let vm = DashboardViewModel(service: service)
        vm.programs = [info, design]
        await vm.loadSessions()

        XCTAssertEqual(vm.totalProspects, 3)
        XCTAssertEqual(vm.rdvCount, 2)
        XCTAssertEqual(vm.noShowCount, 7)
        XCTAssertEqual(vm.byProgram.first?.programId, info.id)
        XCTAssertEqual(vm.byProgram.first?.count, 2)

        vm.filterPrograms = [design.id]
        XCTAssertEqual(vm.totalProspects, 1)
        XCTAssertEqual(vm.byAgent.first?.agentNom, "Hugo")
        XCTAssertFalse(vm.hasRdvTargets)
    }
}

@MainActor
final class ProspectListViewModelTests: XCTestCase {
    func testArchiveRemovesProspectLocally() async {
        let session = TestData.session(status: .termine) // no Live Activity in tests
        let service = MockProspectService()
        let prospect = TestData.prospect(sessionId: session.id)
        service.prospects = [prospect]
        let vm = ProspectListViewModel(session: session, isReadOnly: false, service: service)
        await vm.load()
        XCTAssertEqual(vm.prospects.count, 1)

        await vm.archiveProspect(prospect)

        XCTAssertEqual(service.archivedIds, [prospect.id])
        XCTAssertTrue(vm.prospects.isEmpty)
    }

    func testSearchAndProgramFilter() async {
        let session = TestData.session(status: .termine)
        let program = UUID()
        let service = MockProspectService()
        service.prospects = [
            TestData.prospect(sessionId: session.id, prenom: "Léa", programId: program),
            TestData.prospect(sessionId: session.id, prenom: "Hugo", programId: nil),
        ]
        let vm = ProspectListViewModel(session: session, isReadOnly: true, service: service)
        await vm.load()

        vm.searchText = "hug"
        XCTAssertEqual(vm.filteredProspects.map(\.prenom), ["Hugo"])
        vm.searchText = ""
        vm.filterPrograms = [program]
        XCTAssertEqual(vm.filteredProspects.map(\.prenom), ["Léa"])
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    func testRolePermissions() {
        let organizer = AppState.preview(.organizerFull)
        XCTAssertTrue(organizer.isAdmin)
        XCTAssertTrue(organizer.canEditProspects)
        XCTAssertTrue(organizer.canExport)

        let agent = AppState.preview(.agentFull)
        XCTAssertFalse(agent.isAdmin)
        XCTAssertTrue(agent.canEditProspects)
        XCTAssertFalse(agent.canExport)
    }

    func testFreshPhoneStartsAtOnboarding() {
        XCTAssertEqual(AppState.preview(.fresh).phase, .onboarding)
        XCTAssertEqual(AppState.preview(.organizerEmpty).phase, .ready)
    }

    func testProgramNames() {
        let state = AppState.preview(.organizerFull)
        XCTAssertEqual(state.programName(nil), "No program")
        XCTAssertEqual(state.programName(state.programs[0].id), state.programs[0].name)
    }

    func testOrganizingAndResettingTheDevice() {
        let seeded = DemoSeed.make(.fresh)
        let state = AppState(store: seeded.store, exchange: EventExchange(store: seeded.store, keys: seeded.keys))
        state.startOrganizing(name: "Camille", eventLabel: "JPO")
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.eventLabel, "Session", "every session is just called a session")
        XCTAssertTrue(state.isAdmin)
        state.resetDevice()
        XCTAssertEqual(state.phase, .onboarding)
    }
}
