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

}

import SwiftUI
