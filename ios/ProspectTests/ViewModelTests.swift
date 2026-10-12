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

    func testOfflineSaveIsQueuedAndRetriedWithTheSameId() async {
        let store = PendingProspectStore.shared
        store.removeAll()
        defer { store.removeAll() }
        let service = MockProspectService()
        service.errorToThrow = APIError.network
        let session = TestData.session()
        let vm = ProspectFormViewModel(mode: .create(session: session), programs: programs, authorName: "Hugo", service: service)
        filled(vm)

        let saved = await vm.save()

        XCTAssertEqual(saved?.id, vm.clientId, "the list shows the queued prospect under its final id")
        XCTAssertNil(vm.errorMessage, "going offline is not an error")
        XCTAssertTrue(store.isPending(vm.clientId))

        service.errorToThrow = APIError.network
        var result = await store.flush(using: service)
        XCTAssertTrue(result.sent.isEmpty, "still offline: nothing is lost, nothing is sent")
        XCTAssertEqual(store.items.count, 1)

        service.errorToThrow = nil
        result = await store.flush(using: service)
        XCTAssertEqual(result.sent.count, 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(service.createdInputs.last?.input.clientId, vm.clientId)
    }

    func testRefusedPendingProspectIsDropped() async {
        let store = PendingProspectStore.shared
        store.removeAll()
        defer { store.removeAll() }
        let service = MockProspectService()
        let vm = ProspectFormViewModel(mode: .create(session: TestData.session()), programs: programs, service: service)
        filled(vm)
        service.errorToThrow = APIError.network
        _ = await vm.save()
        service.errorToThrow = APIError(status: 409, code: "event_archived", message: "")
        let result = await store.flush(using: service)
        XCTAssertEqual(result.dropped, 1)
        XCTAssertTrue(store.items.isEmpty)
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
        service.errorToThrow = APIError(status: 403, code: "forbidden", message: "")
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
        // Admins receive join codes, which is what lets the dashboard load conseillers.
        service.summaries = [SessionSummary(session: session, prospectCount: 3, agentCode: "AAAAAA", cfCode: "BBBBBB")]
        service.prospects = [
            TestData.prospect(sessionId: session.id, programId: info.id, statut: .rdvInfo),
            TestData.prospect(sessionId: session.id, programId: info.id, statut: .rdvAdmission),
            TestData.prospect(sessionId: session.id, programId: design.id, statut: .curieux, agent: "Hugo"),
        ]
        service.participants = [
            Participant(id: UUID(), displayName: "Claire", role: .conseillerFormation,
                        programIds: [info.id], lastSeenAt: nil, createdAt: "2026-10-01T09:00:00.000Z"),
            Participant(id: UUID(), displayName: "Hugo", role: .agent,
                        programIds: [], lastSeenAt: nil, createdAt: "2026-10-01T09:00:00.000Z"),
        ]

        let vm = DashboardViewModel(service: service)
        vm.programs = [info, design]
        await vm.loadSessions()

        XCTAssertEqual(vm.totalProspects, 3)
        XCTAssertEqual(vm.rdvCount, 2)
        XCTAssertEqual(vm.noShowCount, 7)
        XCTAssertEqual(vm.byProgram.first?.programId, info.id)
        XCTAssertEqual(vm.byProgram.first?.count, 2)
        XCTAssertEqual(vm.closingByProgram.map(\.program.id), [info.id])
        XCTAssertEqual(vm.closingByProgram.first?.items.first?.total, 2)

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
        let admin = AppState.preview(role: .admin)
        XCTAssertTrue(admin.isAdmin)
        XCTAssertTrue(admin.canEditProspects)
        XCTAssertTrue(admin.canExport)

        let advisor = AppState.preview(role: .conseillerFormation)
        XCTAssertFalse(advisor.isAdmin)
        XCTAssertFalse(advisor.canEditProspects)
        XCTAssertTrue(advisor.canExport)

        let agent = AppState.preview(role: .agent)
        XCTAssertTrue(agent.canEditProspects)
        XCTAssertFalse(agent.canExport)
    }

    func testPreviewRoleOverridesWithoutChangingRealRole() {
        let state = AppState.preview(role: .admin)
        state.previewRole = .agent
        XCTAssertEqual(state.effectiveRole, .agent)
        XCTAssertEqual(state.role, .admin)
        XCTAssertFalse(state.isAdmin)
    }

    func testEventLabelAndProgramNames() {
        let state = AppState.preview(eventLabel: "JPO")
        XCTAssertEqual(state.eventLabel, "JPO")
        XCTAssertEqual(state.programName(nil), "Sans programme")
        XCTAssertEqual(state.programName(state.programs[0].id), state.programs[0].name)
    }
}
