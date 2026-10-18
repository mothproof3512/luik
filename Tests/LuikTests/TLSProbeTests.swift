import XCTest
@testable import Luik

/// Captured-output tests for the certificate tool's parsers: no network, no openssl.
final class TLSProbeTests: XCTestCase {
    static let tls13 = """
    CONNECTED(00000005)
    New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
    Server public key is 2048 bit
    Secure Renegotiation IS NOT supported
    SSL-Session:
        Protocol  : TLSv1.3
        Cipher    : 0000
        Verify return code: 0 (ok)
    """

    static let failed = """
    4567:error:14094410:SSL routines:ssl3_read_bytes:sslv3 alert handshake failure
    New, (NONE), Cipher is (NONE)
    SSL-Session:
        Protocol  : TLSv1.2
        Cipher    : 0000
    """

    static let x509 = """
    Certificate:
        Data:
            Version: 3 (0x2)
            Serial Number:
                03:a1:b2:c3:d4:e5:f6:07:18:29:3a:4b:5c:6d:7e:8f
            Signature Algorithm: sha256WithRSAEncryption
            Issuer: C = US, O = Let's Encrypt, CN = R11
            Validity
                Not Before: Sep  1 10:00:00 2026 GMT
                Not After : Nov 30 10:00:00 2026 GMT
            Subject: CN = www.example.com
            Subject Public Key Info:
                Public Key Algorithm: id-ecPublicKey
                    Public-Key: (256 bit)
                    ASN1 OID: prime256v1
                    NIST CURVE: P-256
            X509v3 extensions:
                X509v3 Key Usage: critical
                    Digital Signature
                X509v3 Extended Key Usage:
                    TLS Web Server Authentication, TLS Web Client Authentication
                X509v3 Basic Constraints: critical
                    CA:FALSE
                X509v3 Subject Key Identifier:
                    AA:BB:CC
                X509v3 Authority Key Identifier:
                    keyid:11:22:33
                Authority Information Access:
                    OCSP - URI:http://r11.o.lencr.org
                    CA Issuers - URI:http://r11.i.lencr.org/
                X509v3 Subject Alternative Name:
                    DNS:www.example.com, DNS:example.com, DNS:*.app.example.com
                X509v3 Certificate Policies:
                    Policy: 2.23.140.1.2.1
                X509v3 CRL Distribution Points:
                    Full Name:
                      URI:http://crl.example.test/r11.crl
                CT Precertificate SCTs:
                    Signed Certificate Timestamp:
                        Version   : v1 (0x0)
                    Signed Certificate Timestamp:
                        Version   : v1 (0x0)
        Signature Algorithm: sha256WithRSAEncryption
        Signature Value:
            00:11
    SHA256 Fingerprint=AB:CD:EF
    """

    func testNegotiatedProtocolAndCipher() {
        XCTAssertEqual(TLSProbe.negotiatedProtocol(Self.tls13), "TLSv1.3")
        XCTAssertEqual(TLSProbe.negotiatedCipher(Self.tls13), "TLS_AES_256_GCM_SHA384")   // not the 0000 ID from the session block
        XCTAssertNil(TLSProbe.negotiatedCipher(Self.failed))
        XCTAssertEqual(TLSProbe.negotiatedProtocol("New, TLSv1/SSLv3, Cipher is AES128-SHA\nSSL-Session:\n    Protocol  : TLSv1.1\n"), "TLSv1.1")
        XCTAssertEqual(TLSProbe.negotiatedProtocol("New, TLSv1.0, Cipher is AES128-SHA\n"), "TLSv1")
    }

    func testLocalProblems() {
        XCTAssertNotNil(TLSProbe.localProblem("s_client: Unknown option: -ssl3"))
        XCTAssertNotNil(TLSProbe.localProblem("error:0A0000BF:SSL routines:tls_setup_handshake:no protocols available"))
        XCTAssertNil(TLSProbe.localProblem(Self.failed))
    }

    func testCertificateTextParsing() {
        let cert = TLSInspector.parseCertificateText(Self.x509)
        XCTAssertEqual(cert.commonName, "www.example.com")
        XCTAssertEqual(cert.issuerName, "R11")
        XCTAssertEqual(cert.issuerOrganisation, "Let's Encrypt")
        XCTAssertEqual(cert.serial, "03:a1:b2:c3:d4:e5:f6:07:18:29:3a:4b:5c:6d:7e:8f")
        XCTAssertEqual(cert.sans, ["www.example.com", "example.com", "*.app.example.com"])
        XCTAssertEqual(cert.wildcardNames, ["*.app.example.com"])
        XCTAssertEqual(cert.keyBits, 256)
        XCTAssertTrue(cert.keyType.contains("ecPublicKey"))
        XCTAssertTrue(cert.keyType.contains("P-256"))
        XCTAssertEqual(cert.signatureAlgorithm, "sha256WithRSAEncryption")
        XCTAssertEqual(cert.keyUsage, "Digital Signature")
        XCTAssertEqual(cert.extendedKeyUsage, "TLS Web Server Authentication, TLS Web Client Authentication")
        XCTAssertFalse(cert.isCA)
        XCTAssertEqual(cert.subjectKeyID, "AA:BB:CC")
        XCTAssertEqual(cert.authorityKeyID, "11:22:33")
        XCTAssertEqual(cert.ocspURLs, ["http://r11.o.lencr.org"])
        XCTAssertEqual(cert.caIssuerURLs, ["http://r11.i.lencr.org/"])
        XCTAssertEqual(cert.crlURLs, ["http://crl.example.test/r11.crl"])
        XCTAssertEqual(cert.policies, ["2.23.140.1.2.1"])
        XCTAssertEqual(cert.validationLevel, "DV (domain validated)")
        XCTAssertEqual(cert.sctCount, 2)
        XCTAssertEqual(cert.fingerprintSHA256, "AB:CD:EF")
        XCTAssertNotNil(cert.notBefore)
        XCTAssertNotNil(cert.notAfter)
        XCTAssertEqual(cert.lifetimeDays, 90)
        XCTAssertFalse(cert.isSelfSigned)
    }

    func testNameMatching() {
        XCTAssertTrue(TLSInspector.matches(host: "www.example.com", san: "www.example.com"))
        XCTAssertTrue(TLSInspector.matches(host: "api.app.example.com", san: "*.app.example.com"))
        XCTAssertFalse(TLSInspector.matches(host: "deep.api.app.example.com", san: "*.app.example.com"))
        XCTAssertFalse(TLSInspector.matches(host: "app.example.com", san: "*.app.example.com"))
    }

    func testSelfSignedAndRootDetection() {
        var root = TLSCertificate(); root.subject = "CN = ISRG Root X1"; root.issuer = "CN = ISRG Root X1"
        var leaf = TLSCertificate(); leaf.subject = "CN = nhr.nl"; leaf.issuer = "CN = R11"
        XCTAssertTrue(root.isSelfSigned)
        XCTAssertFalse(leaf.isSelfSigned)
    }

    func testPEMBlocks() {
        let text = "junk\n-----BEGIN CERTIFICATE-----\nAAA\n-----END CERTIFICATE-----\nmore\n-----BEGIN CERTIFICATE-----\nBBB\n-----END CERTIFICATE-----\n"
        XCTAssertEqual(TLSInspector.pemBlocks(in: text).count, 2)
    }
}
