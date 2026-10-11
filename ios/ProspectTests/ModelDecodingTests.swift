// ProspectTests/ModelDecodingTests.swift
// The app's models must decode exactly what the API (api/src/routes) returns.
import XCTest
@testable import Prospect

final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodesProspect() throws {
        let json = """
        {"id":"7b0c1f3e-1d1a-4c8e-9a2b-0f0e0d0c0b0a","event_id":"11111111-2222-4333-8444-555555555555",
         "first_name":"Léa","last_name":"Durand","email":"lea@exemple.fr","phone":"+33 6 12 34 56 78",
         "program_id":null,"education_level":"Terminale","status":"Rdv d'info pris","notes":"🙂",
         "created_by":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","created_by_name":"Bob",
         "created_at":"2026-11-14T10:00:00.123Z","updated_at":"2026-11-14T10:05:00.000Z","deleted_at":null}
        """
        let p = try decoder.decode(Prospect.self, from: Data(json.utf8))
        XCTAssertEqual(p.fullName, "Léa Durand")
        XCTAssertNil(p.programId)
        XCTAssertEqual(p.statutEnum, .rdvInfo)
        XCTAssertEqual(p.agentNom, "Bob")
        XCTAssertNil(p.deletedAt)
    }

    func testDecodesEventSummaryWithObjectives() throws {
        let programId = UUID()
        let json = """
        {"id":"11111111-2222-4333-8444-555555555555","name":"Salon","date":"2026-11-14","status":"en_cours",
         "is_archived":false,"pre_registered":40,"rdv_target_low":10,"rdv_target_high":15,
         "program_objectives":{"\(programId.uuidString.lowercased())":7,"not-a-uuid":3},
         "created_at":"2026-10-01T09:00:00.000Z","prospect_count":12}
        """
        let s = try decoder.decode(SessionSummary.self, from: Data(json.utf8))
        XCTAssertEqual(s.statutSession, .enCours)
        XCTAssertEqual(s.prospectCount, 12)
        XCTAssertEqual(s.programObjectives, [programId: 7]) // malformed keys are dropped
        XCTAssertEqual(s.session.displayDate.map(Session.isoDay), "2026-11-14")
    }

    func testDecodesAdminMe() throws {
        let json = """
        {"kind":"admin","user":{"id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","email":"a@b.co","display_name":"Alice"},
         "organizations":[{"id":"11111111-2222-4333-8444-555555555555","name":"Acme","event_label":"JPO","admin_code":"K7M2QX",
           "created_at":"2026-10-01T09:00:00.000Z","role":"admin","display_name":"Alice","program_ids":[]}]}
        """
        guard case .admin(let user, let orgs) = try decoder.decode(MeResponse.self, from: Data(json.utf8)) else {
            return XCTFail("expected admin")
        }
        XCTAssertEqual(user.displayName, "Alice")
        XCTAssertEqual(orgs.first?.adminCode, "K7M2QX")
        XCTAssertEqual(orgs.first?.eventLabel, "JPO")
    }

    func testDecodesParticipantMe() throws {
        let json = """
        {"kind":"participant","participant":{"id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","display_name":"Hugo","role":"conseiller_formation"},
         "organization":{"id":"11111111-2222-4333-8444-555555555555","name":"Acme","event_label":"Salon",
           "created_at":"2026-10-01T09:00:00.000Z","role":"conseiller_formation","display_name":"Hugo","program_ids":[]},
         "event":{"id":"22222222-2222-4333-8444-555555555555","name":"Salon","date":"2026-11-14","status":"en_cours",
           "is_archived":false,"pre_registered":0,"rdv_target_low":0,"rdv_target_high":0,"program_objectives":{},
           "created_at":"2026-10-01T09:00:00.000Z","prospect_count":0}}
        """
        guard case .participant(let me, let org, let event) = try decoder.decode(MeResponse.self, from: Data(json.utf8)) else {
            return XCTFail("expected participant")
        }
        XCTAssertEqual(me.role, .conseillerFormation)
        XCTAssertNil(org.adminCode)
        XCTAssertNil(event.agentCode, "participants never receive join codes")
    }

    func testDecodesParticipant() throws {
        let json = """
        {"id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","display_name":"Bob","role":"agent",
         "program_ids":[],"last_seen_at":null,"created_at":"2026-10-01T09:00:00.000Z"}
        """
        let p = try decoder.decode(Participant.self, from: Data(json.utf8))
        XCTAssertEqual(p.role, .agent)
    }

    func testProspectInputAlwaysSendsNullableFields() throws {
        let input = ProspectInput(prenom: "A", nom: "B", email: "a@b.co", telephone: "123456",
                                  programId: nil, niveauActuel: "Terminale", statut: "Curieux", notes: nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any]
        XCTAssertTrue(object?["program_id"] is NSNull, "program_id must be sent as null so it can be cleared")
        XCTAssertTrue(object?["notes"] is NSNull)
        XCTAssertEqual(object?["first_name"] as? String, "A")
    }

    func testSessionPatchOmitsUnsetFields() throws {
        let data = try JSONEncoder().encode(SessionPatch(status: .termine))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?.count, 1)
        XCTAssertEqual(object?["status"] as? String, "termine")
    }

    func testProgramColorParsing() {
        XCTAssertNotNil(Color.rgbComponents(hex: "#3366E6"))
        XCTAssertNil(Color.rgbComponents(hex: "#XYZ"))
    }

    func testAPIErrorMessages() {
        XCTAssertEqual(APIError(status: 409, code: "last_admin", message: "").errorDescription,
                       "Une organisation doit garder au moins un administrateur.")
        XCTAssertEqual(APIError.network.errorDescription, "Erreur réseau — vérifiez votre connexion.")
    }
}

import SwiftUI
