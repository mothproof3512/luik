import XCTest
@testable import Luik

/// Captured-output tests for the TLS probe decisions: no network, no openssl.
final class TLSProbeTests: XCTestCase {
    // A TLS 1.3 handshake as OpenSSL/LibreSSL print it — including LibreSSL's "0000" cipher ID
    // in the session block, which is the line the old code read.
    static let tls13 = """
    CONNECTED(00000005)
    ---
    Certificate chain
     0 s:CN = nhr.nl
       i:C = US, O = Let's Encrypt, CN = R11
    ---
    New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
    Server public key is 2048 bit
    Secure Renegotiation IS NOT supported
    Compression: NONE
    Expansion: NONE
    SSL-Session:
        Protocol  : TLSv1.3
        Cipher    : 0000
        Verify return code: 0 (ok)
    ---
    """

    static let tls12AEAD = """
    CONNECTED(00000005)
    ---
    New, TLSv1.2, Cipher is ECDHE-RSA-AES256-GCM-SHA384
    Server public key is 2048 bit
    Secure Renegotiation IS supported
    Compression: NONE
    Expansion: NONE
    SSL-Session:
        Protocol  : TLSv1.2
        Cipher    : ECDHE-RSA-AES256-GCM-SHA384
        Verify return code: 0 (ok)
    ---
    """

    static let tls12RC4 = """
    New, TLSv1.2, Cipher is ECDHE-RSA-RC4-SHA
    Secure Renegotiation IS supported
    SSL-Session:
        Protocol  : TLSv1.2
        Cipher    : ECDHE-RSA-RC4-SHA
    """

    static let tls10 = """
    New, TLSv1.0, Cipher is AES128-SHA
    Secure Renegotiation IS supported
    SSL-Session:
        Protocol  : TLSv1
        Cipher    : AES128-SHA
    """

    static let failed = """
    CONNECTED(00000005)
    4567:error:14094410:SSL routines:ssl3_read_bytes:sslv3 alert handshake failure
    ---
    no peer certificate available
    ---
    New, (NONE), Cipher is (NONE)
    SSL-Session:
        Protocol  : TLSv1.2
        Cipher    : 0000
    """

    static let noProtocols = """
    4567:error:141E70BF:SSL routines:tls_construct_client_hello:no protocols available
    """

    static let unknownOption = """
    s_client: Unknown option: -ssl3
    """

    // MARK: Parsing

    func testNegotiatedProtocolPrefersHandshakeLine() {
        XCTAssertEqual(TLSProbe.negotiatedProtocol(Self.tls13), "TLSv1.3")
        XCTAssertEqual(TLSProbe.negotiatedProtocol(Self.tls10), "TLSv1")   // "TLSv1.0" on the New line, "TLSv1" in the session block
        XCTAssertEqual(TLSProbe.negotiatedProtocol("New, TLSv1/SSLv3, Cipher is AES128-SHA\nSSL-Session:\n    Protocol  : TLSv1.1\n"), "TLSv1.1")
        XCTAssertNil(TLSProbe.negotiatedProtocol(""))
    }

    func testCipherIDZeroIsNeverACipher() {
        XCTAssertEqual(TLSProbe.negotiatedCipher(Self.tls13), "TLS_AES_256_GCM_SHA384")
        XCTAssertNil(TLSProbe.negotiatedCipher(Self.failed))
        XCTAssertNil(TLSProbe.negotiatedCipher("SSL-Session:\n    Cipher    : 0000\n"))
    }

    // MARK: Protocol probes

    func testProtocolProbeAcceptedOnlyWhenVersionMatches() {
        XCTAssertEqual(TLSProbe.evaluateProtocol(flag: "-tls1_3", output: Self.tls13).verdict, .accepted)
        XCTAssertEqual(TLSProbe.evaluateProtocol(flag: "-tls1_2", output: Self.tls12AEAD).verdict, .accepted)
        XCTAssertEqual(TLSProbe.evaluateProtocol(flag: "-tls1", output: Self.tls10).verdict, .accepted)
    }

    func testProtocolProbeThatEndsOnAnotherVersionIsNotAccepted() {
        // The old false positive: asked for TLS 1.0, the client ignored it and got TLS 1.3.
        let outcome = TLSProbe.evaluateProtocol(flag: "-tls1", output: Self.tls13)
        XCTAssertFalse(outcome.verdict.isAccepted)
        if case .notTestable = outcome.verdict {} else { XCTFail("expected notTestable, got \(outcome.verdict)") }
    }

    func testProtocolProbeHandshakeFailureIsRefused() {
        XCTAssertEqual(TLSProbe.evaluateProtocol(flag: "-tls1_1", output: Self.failed).verdict, .refused)
    }

    func testProtocolProbeLocalProblemsAreNotTestable() {
        if case .notTestable = TLSProbe.evaluateProtocol(flag: "-tls1", output: Self.noProtocols).verdict {} else { XCTFail() }
        if case .notTestable = TLSProbe.evaluateProtocol(flag: "-ssl3", output: Self.unknownOption).verdict {} else { XCTFail() }
    }

    // MARK: Cipher-family probes

    func testCipherFamilyProbeAcceptedOnlyForAMemberOfTheFamily() {
        let rc4: Set<String> = ["ECDHE-RSA-RC4-SHA", "RC4-SHA", "RC4-MD5"]
        XCTAssertEqual(TLSProbe.evaluateCipherFamily(family: rc4, output: Self.tls12RC4).verdict, .accepted)
    }

    func testCipherFamilyProbeOnTLS13IsNotAResult() {
        // -cipher does not touch TLS 1.3 suites: a 1.3 handshake proves nothing about RC4.
        let rc4: Set<String> = ["ECDHE-RSA-RC4-SHA", "RC4-SHA"]
        let outcome = TLSProbe.evaluateCipherFamily(family: rc4, output: Self.tls13)
        XCTAssertFalse(outcome.verdict.isAccepted)
    }

    func testCipherFamilyProbeWithAnotherCipherIsNotAccepted() {
        // Asked for RC4, server answered with an AEAD suite on 1.2: the list was not applied.
        let rc4: Set<String> = ["ECDHE-RSA-RC4-SHA", "RC4-SHA"]
        let outcome = TLSProbe.evaluateCipherFamily(family: rc4, output: Self.tls12AEAD)
        XCTAssertFalse(outcome.verdict.isAccepted)
        XCTAssertNotEqual(outcome.verdict, .refused)
    }

    func testCipherFamilyProbeHandshakeFailureIsRefused() {
        let rc4: Set<String> = ["RC4-SHA"]
        XCTAssertEqual(TLSProbe.evaluateCipherFamily(family: rc4, output: Self.failed).verdict, .refused)
    }

    func testEmptyFamilyIsNotTestable() {
        if case .notTestable = TLSProbe.evaluateCipherFamily(family: [], output: Self.tls12AEAD).verdict {} else { XCTFail() }
    }

    func testCipherNamesParsing() {
        XCTAssertEqual(TLSProbe.cipherNames(fromCiphersOutput: "TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256:RC4-SHA:RC4-MD5\n"), ["RC4-SHA", "RC4-MD5"])
        XCTAssertEqual(TLSProbe.cipherNames(fromCiphersOutput: "Error in cipher list\n140:error:1410D0B9:SSL routines:no cipher match\n"), [])
    }

    // MARK: Renegotiation

    func testRenegotiationIsJudgedOnTLS12Only() {
        XCTAssertEqual(TLSProbe.secureRenegotiation(tls12Output: Self.tls12AEAD), true)
        // A 1.3 handshake always says "NOT supported": no verdict from it.
        XCTAssertNil(TLSProbe.secureRenegotiation(tls12Output: Self.tls13))
        XCTAssertNil(TLSProbe.secureRenegotiation(tls12Output: nil))
    }

    // MARK: The nhr.nl shape: TLS 1.2 + 1.3 with AEAD suites only → no warnings

    func testModernServerProducesNoProtocolOrCipherWarnings() {
        let probes: [(String, String)] = [("-ssl3", Self.unknownOption), ("-tls1", Self.tls13), ("-tls1_1", Self.failed), ("-tls1_2", Self.tls12AEAD), ("-tls1_3", Self.tls13)]
        let accepted = probes.filter { TLSProbe.evaluateProtocol(flag: $0.0, output: $0.1).verdict.isAccepted }.map { $0.0 }
        XCTAssertEqual(accepted, ["-tls1_2", "-tls1_3"])
        let families: [Set<String>] = [["NULL-SHA", "AECDH-AES128-SHA"], ["EXP-RC4-MD5"], ["RC4-SHA"], ["DES-CBC3-SHA"], ["AES128-SHA", "AES256-SHA"], ["AES128-GCM-SHA256", "AES256-SHA"]]
        // Every family probe came back on an AEAD ECDHE suite (the server has nothing else).
        let acceptedFamilies = families.filter { TLSProbe.evaluateCipherFamily(family: $0, output: Self.tls12AEAD).verdict.isAccepted }
        XCTAssertTrue(acceptedFamilies.isEmpty)
        XCTAssertEqual(TLSProbe.secureRenegotiation(tls12Output: Self.tls12AEAD), true)
    }

    // MARK: Chain

    func testRootIncludedInChainIsDetected() {
        var leaf = TLSCertificate(); leaf.subject = "CN = nhr.nl"; leaf.issuer = "CN = R11"
        var intermediate = TLSCertificate(); intermediate.subject = "CN = R11"; intermediate.issuer = "CN = ISRG Root X1"
        var root = TLSCertificate(); root.subject = "CN = ISRG Root X1"; root.issuer = "CN = ISRG Root X1"
        XCTAssertFalse(leaf.isSelfSigned)
        XCTAssertFalse(intermediate.isSelfSigned)
        XCTAssertTrue(root.isSelfSigned)
    }
}
