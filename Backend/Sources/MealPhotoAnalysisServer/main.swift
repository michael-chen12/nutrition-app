// Thin HTTP server for meal photo analysis and food search. Every decision lives in `MealPhotoAnalysisService`
// and `FoodSearchService`; this file only moves bytes between HTTP and the services. Not built on Windows (see
// Package.swift).
//
// Environment: GEMINI_API_KEY (required for analysis; never logged), GEMINI_MODEL (optional), FDC_API_KEY
// (required for food search; never logged), PORT (default 8080), HOST (default 127.0.0.1, so the development
// backend is reachable only from this machine).

import AnalysisContract
import AUSNUT
import Foundation
import Hummingbird
import MealPhotoAnalysis
import NIOCore

let environment = ProcessInfo.processInfo.environment
let configuration = GeminiConfiguration(environment: environment)
let service = MealPhotoAnalysisService(configuration: configuration, transport: URLSessionProviderTransport())
let foodDataCentral = FoodDataCentralConfiguration(environment: environment)
let foodSearch = FoodSearchService(
    configuration: foodDataCentral,
    transport: URLSessionProviderTransport(timeout: 20),
    ausnut: try AUSNUTDataset.packaged()
)

if configuration.credential == nil {
    print("GEMINI_API_KEY is not set: photo analysis requests will be answered with notConfigured.")
}
if foodDataCentral.credential == nil {
    print("FDC_API_KEY is not set: food search requests will be answered with notConfigured.")
}
print("Using Gemini model \(configuration.model). Re-verify the model, quota and terms in the developer account.")

func response(_ reply: AnalysisHTTPResponse) -> Response {
    Response(
        status: HTTPResponse.Status(code: reply.statusCode),
        headers: [.contentType: reply.contentType],
        body: ResponseBody(byteBuffer: ByteBuffer(bytes: reply.body))
    )
}

let router = Router()
router.post(RouterPath(stringLiteral: MealPhotoAnalysisEndpoint.path)) { request, _ -> Response in
    // Slightly above the service's image limit so oversized uploads get its clear error message.
    let body = try await request.body.collect(upTo: MealPhotoAnalysisService.maximumTotalImageBytes * 2)
    return response(await service.handle(requestBody: Data(body.readableBytesView)))
}
router.post(RouterPath(stringLiteral: FoodSearchEndpoint.path)) { request, _ -> Response in
    let body = try await request.body.collect(upTo: 16 * 1024)
    return response(await foodSearch.handle(requestBody: Data(body.readableBytesView)))
}

let app = Application(
    router: router,
    configuration: ApplicationConfiguration(
        address: .hostname(environment["HOST"] ?? "127.0.0.1", port: Int(environment["PORT"] ?? "") ?? 8080)
    )
)
try await app.runService()
