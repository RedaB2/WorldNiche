import Foundation

private let avatarUser = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let oldPhotoPath = "11111111-1111-4111-8111-111111111111/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg"
private let fixtureJPEG = Data([0xff, 0xd8, 1, 2, 3, 4, 0xff, 0xd9])
private final class AvatarVault: SocialSessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data? = try! JSONEncoder().encode(SocialSession(accessToken: "avatar-test-token", refreshToken: "test-refresh",
        expiresAt: Date().timeIntervalSince1970 + 3600, user: .init(id: avatarUser, email: "test@example.invalid")))
    func load() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func save(_ value: Data) throws { lock.lock(); defer { lock.unlock() }; data = value }
    func clear() throws { lock.lock(); defer { lock.unlock() }; data = nil }
}
private final class AvatarFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String? = oldPhotoPath
    private var objects: [String: Data] = [oldPhotoPath:fixtureJPEG]
    private var calls = 0
    private var mode = "normal"
    private var committed = false
    private var uploadFailure: (Int, Data)?
    func reset(_ mode: String = "normal") { lock.lock(); defer { lock.unlock() }; current=oldPhotoPath; objects=[oldPhotoPath:fixtureJPEG]; calls=0; self.mode=mode; committed=false; uploadFailure=nil }
    func rejectNextUpload(status: Int, json: String) { lock.lock(); defer { lock.unlock() }; uploadFailure=(status,Data(json.utf8)) }
    func snapshot() -> (path:String?, objects:[String:Data],calls:Int) { lock.lock(); defer { lock.unlock() }; return(current,objects,calls) }
    func reply(_ request: URLRequest) -> (Int,Data) {
        lock.lock(); defer { lock.unlock() }; calls += 1
        guard request.url?.host == "avatar.example.invalid", request.value(forHTTPHeaderField:"Authorization") == "Bearer avatar-test-token" else { return(403,Data()) }
        var bytes=request.httpBody ?? Data()
        if let stream=request.httpBodyStream { stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:1024);while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};bytes.append(buffer,count:n)} }
        let json=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] ?? [:]
        func encoded(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject:object) }
        func profile() -> Data { encoded(["id":avatarUser.uuidString,"display_name":"Explorer","avatar":"globe","share_exploration":false,"avatar_path":current as Any? ?? NSNull()]) }
        let path=request.url!.path
        if path == "/rest/v1/rpc/get_my_profile" {
            if mode == "uncertain", committed { return(503,encoded(["error":"unavailable"])) }
            return(200,profile())
        }
        if path == "/rest/v1/rpc/set_profile_avatar" {
            if mode == "reject" { return(400,encoded(["error":"rejected"])) }
            current=json["p_path"] as? String;committed=true
            if mode == "lost" || mode == "uncertain" { return(503,encoded(["error":"lost_response"])) }
            return(200,profile())
        }
        let uploadPrefix="/storage/v1/object/profile-photos/"
        if path.hasPrefix(uploadPrefix),request.httpMethod == "POST" {
            if let failure=uploadFailure { uploadFailure=nil; return failure }
            guard request.value(forHTTPHeaderField:"Content-Type") == "image/jpeg", request.value(forHTTPHeaderField:"x-upsert") == "false", bytes == fixtureJPEG else { return(400,Data()) }
            objects[String(path.dropFirst(uploadPrefix.count))]=bytes
            return(200,encoded(["Key":"uploaded"]))
        }
        if path == "/storage/v1/object/profile-photos",request.httpMethod == "DELETE" {
            for path in json["prefixes"] as? [String] ?? [] { objects.removeValue(forKey:path) }
            return(200,encoded([]))
        }
        let readPrefix="/storage/v1/object/authenticated/profile-photos/"
        if path.hasPrefix(readPrefix),request.httpMethod == "GET",request.value(forHTTPHeaderField:"Cache-Control") == "no-store" {
            let object=String(path.dropFirst(readPrefix.count))
            if let bytes=objects[object] { return(200,bytes) }
            return(403,Data())
        }
        return(400,Data())
    }
}
private final class AvatarProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = AvatarFixture()
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        let (status,data)=Self.fixture.reply(request)
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor enum AvatarAPIChecks {
    static func run() async throws -> Int {
        var count=0
        func check(_ value:Bool,_ label:String) { guard value else {fatalError("FAIL \(label)")};count+=1;print("PASS \(label)") }
        let configuration=SocialConfiguration(serviceURL:URL(string:"https://avatar.example.invalid")!,publicAPIKey:"test-public",invitationHost:"example.invalid",privacyPolicyURL:nil,supportURL:nil)
        func api() -> SocialAPI {
            let transport=URLSessionConfiguration.ephemeral;transport.protocolClasses=[AvatarProtocol.self];transport.urlCache=nil
            return SocialAPI(configuration:configuration,transport:URLSession(configuration:transport),vault:AvatarVault())
        }
        AvatarProtocol.fixture.reset();let service=api()
        let changed=try await service.updateProfilePhoto(fixtureJPEG)
        check(changed.avatarPath != nil && changed.avatarPath != oldPhotoPath,"Upload commits a fresh private path")
        check(AvatarProtocol.fixture.snapshot().objects.count == 1,"Replacement removes old object")
        let downloaded=try await service.avatarData(path:changed.avatarPath!)
        check(downloaded == fixtureJPEG,"Authenticated no-store download returns photo")
        let removed=try await service.updateProfilePhoto(nil)
        check(removed.avatarPath == nil && AvatarProtocol.fixture.snapshot().objects.isEmpty,"Removing photo clears reference and object")
        AvatarProtocol.fixture.reset("lost")
        let recovered=try await api().updateProfilePhoto(fixtureJPEG)
        check(recovered.avatarPath == AvatarProtocol.fixture.snapshot().path,"Lost commit response reconciles current profile")
        check(AvatarProtocol.fixture.snapshot().objects.count == 1,"Reconciled commit retains new photo and deletes old one")
        AvatarProtocol.fixture.reset("reject")
        do {_ = try await api().updateProfilePhoto(fixtureJPEG);fatalError("Rejected commit succeeded")} catch {count+=1;print("PASS Rejected commit reports failure")}
        check(AvatarProtocol.fixture.snapshot().objects == [oldPhotoPath:fixtureJPEG],"Rejected commit removes only unselected upload")
        AvatarProtocol.fixture.reset("uncertain")
        do {_ = try await api().updateProfilePhoto(fixtureJPEG);fatalError("Uncertain commit succeeded")} catch {count+=1;print("PASS Uncertain commit reports failure")}
        check(AvatarProtocol.fixture.snapshot().objects.count == 2,"Uncertain commit never deletes possibly selected photo")
        AvatarProtocol.fixture.reset();let guarded=api()
        do {_ = try await guarded.avatarData(path:"https://attacker.invalid/avatar.jpg");fatalError("Remote URL accepted")}catch{count+=1;print("PASS Arbitrary photo URL rejected")}
        check(AvatarProtocol.fixture.snapshot().calls == 0,"Invalid path never contacts network")
        do {_ = try await guarded.updateProfilePhoto(Data("invalid".utf8));fatalError("Invalid upload accepted")}catch{count+=1;print("PASS Invalid upload rejected")}
        check(AvatarProtocol.fixture.snapshot().objects == [oldPhotoPath:fixtureJPEG],"Invalid upload leaves old photo intact")
        let uploadFailures: [(Int,String,SocialError)] = [
            (429,#"{"error":"too_many_requests"}"#,.rateLimited),
            (500,#"{"code":"DatabaseError","error":"DatabaseError","message":"database error, code: PT429"}"#,.rateLimited),
            (500,#"{"error":"DatabaseError","message":"database error, code: PT429"}"#,.rateLimited),
            (400,#"{"code":"PT429","message":"Please wait before trying again."}"#,.rateLimited),
            (500,#"{"code":"DatabaseError","message":"database error, code: P0001"}"#,.unavailable),
            (500,#"{"code":"DatabaseError","message":"connection failed"}"#,.unavailable),
            (403,#"{"code":"AccessDenied","message":"database error, code: PT429"}"#,.rejected)
        ]
        for (index,failure) in uploadFailures.enumerated() {
            AvatarProtocol.fixture.reset()
            AvatarProtocol.fixture.rejectNextUpload(status:failure.0,json:failure.1)
            let limited=api()
            do { _ = try await limited.updateProfilePhoto(fixtureJPEG); fatalError("Rejected upload succeeded") }
            catch { check((error as? SocialError)?.localizedDescription == failure.2.localizedDescription,"Upload failure \(index) uses the specific safe error") }
            let state=AvatarProtocol.fixture.snapshot()
            check(state.path == oldPhotoPath && state.objects == [oldPhotoPath:fixtureJPEG] && state.calls == 2,
                  "Upload failure \(index) retains the old photo and never submits or deletes an object")
            let retried=try await limited.updateProfilePhoto(fixtureJPEG)
            check(retried.avatarPath != oldPhotoPath && AvatarProtocol.fixture.snapshot().objects.count == 1,
                  "Upload failure \(index) allows an explicit later retry")
        }
        return count
    }
}
