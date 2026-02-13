// This file contains struct definitions for parsing the
// `services` section of an OPA configuration file.
// See: https://www.openpolicyagent.org/docs/configuration#services
import Foundation

// MARK: - REST Client Configuration
// From: v1/plugins/rest/rest.go

/// Configuration for a REST client service
public struct RestClientServiceConfig: Codable {
    public let name: String
    public let url: URL
    public let headers: [String: String]
    public let allowInsecureTLS: Bool?
    public let responseHeaderTimeoutSeconds: Int64?
    public let tls: ServerTLSConfig?
    public let credentials: Credentials?
    public let type: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case url
        case headers
        case allowInsecureTLS = "allow_insecure_tls"
        case responseHeaderTimeoutSeconds = "response_header_timeout_seconds"
        case tls
        case credentials
        case type
    }

    public init(
        name: String,
        url: URL,
        headers: [String: String] = [:],
        allowInsecureTLS: Bool? = nil,
        responseHeaderTimeoutSeconds: Int64? = nil,
        tls: ServerTLSConfig? = nil,
        credentials: Credentials? = nil,
        type: String? = nil
    ) {
        self.name = name
        self.url = url
        self.headers = headers
        self.allowInsecureTLS = allowInsecureTLS
        self.responseHeaderTimeoutSeconds = responseHeaderTimeoutSeconds
        self.tls = tls
        self.credentials = credentials
        self.type = type
    }

    // MARK: - Credentials (tagged union)

    /// Credentials represents the default set of REST client credential
    /// options supported by OPA for fetching bundles from remote sources.
    ///
    /// If a custom plugin name is provided, there won't be any associated
    /// config keys in this section-- any configuration will appear under the
    /// `plugins` section.
    public enum Credentials: Codable {
        case bearer(BearerAuthPlugin)
        case oauth2([String: AnyCodable])
        case clientTLS(ClientTLSAuthPlugin)
        case s3Signing([String: AnyCodable])
        case gcpMetadata([String: AnyCodable])
        case azureManagedIdentity(AzureManagedIdentitiesAuthPlugin)
        case custom(String)

        // MARK: - Codable Implementation

        private enum CodingKeys: String, CodingKey {
            case bearer
            case oauth2
            case clientTLS = "client_tls"
            case s3Signing = "s3_signing"
            case gcpMetadata = "gcp_metadata"
            case azureManagedIdentity = "azure_managed_identity"
            case custom = "plugin"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Check if plugin field is present.
            if let pluginName = try container.decodeIfPresent(String.self, forKey: .custom) {
                self = .custom(pluginName)
            } else {
                // Fall back to trying each credential type.
                let attemptedCredentialTypes: [Credentials?] = [
                    try? container.decodeIfPresent(BearerAuthPlugin.self, forKey: .bearer).map { .bearer($0) },
                    try? container.decodeIfPresent([String: AnyCodable].self, forKey: .oauth2).map { .oauth2($0) },
                    try? container.decodeIfPresent(ClientTLSAuthPlugin.self, forKey: .clientTLS).map { .clientTLS($0) },
                    try? container.decodeIfPresent([String: AnyCodable].self, forKey: .s3Signing).map {
                        .s3Signing($0)
                    },
                    try? container.decodeIfPresent([String: AnyCodable].self, forKey: .gcpMetadata).map {
                        .gcpMetadata($0)
                    },
                    try? container.decodeIfPresent(AzureManagedIdentitiesAuthPlugin.self, forKey: .azureManagedIdentity)
                        .map {
                            .azureManagedIdentity($0)
                        },
                ]

                let foundCredentials = attemptedCredentialTypes.compactMap { $0 }

                guard foundCredentials.count == 1 else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath,
                            debugDescription: foundCredentials.isEmpty
                                ? "No valid credential type found"
                                : "Expected exactly one credential type, but found \(foundCredentials.count)"
                        )
                    )
                }

                self = foundCredentials[0]
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .bearer(let plugin):
                try container.encode(plugin, forKey: .bearer)
            case .oauth2(let config):
                try container.encode(config, forKey: .oauth2)
            case .clientTLS(let plugin):
                try container.encode(plugin, forKey: .clientTLS)
            case .s3Signing(let config):
                try container.encode(config, forKey: .s3Signing)
            case .gcpMetadata(let config):
                try container.encode(config, forKey: .gcpMetadata)
            case .azureManagedIdentity(let config):
                try container.encode(config, forKey: .azureManagedIdentity)
            case .custom(let plugin):
                try container.encode(plugin, forKey: .custom)
            }
        }
    }
}

// MARK: - Server TLS Configuration
// From: v1/plugins/rest/auth.go

public struct ServerTLSConfig: Codable {
    public let caCert: String?
    public let systemCARequired: Bool?

    public init(
        caCert: String? = nil,
        systemCARequired: Bool? = nil
    ) {
        self.caCert = caCert
        self.systemCARequired = systemCARequired
    }

    private enum CodingKeys: String, CodingKey {
        case caCert = "ca_cert"
        case systemCARequired = "system_ca_required"
    }
}

// MARK: - Bearer Authentication Plugin
// From: v1/plugins/rest/auth.go

/// Authentication via a bearer token in the HTTP Authorization header
public struct BearerAuthPlugin: Codable {
    public let token: String?
    public let tokenPath: String?
    public let scheme: String?

    public init(
        token: String? = nil,
        tokenPath: String? = nil,
        scheme: String? = nil
    ) {
        self.token = token
        self.tokenPath = tokenPath
        self.scheme = scheme
    }

    private enum CodingKeys: String, CodingKey {
        case token
        case tokenPath = "token_path"
        case scheme
    }
}

// MARK: - Client TLS Authentication Plugin
// From: v1/plugins/rest/auth.go

/// Authentication via client certificate on a TLS connection
public struct ClientTLSAuthPlugin: Codable {
    public let cert: String
    public let privateKey: String
    public let privateKeyPassphrase: String?
    /// Deprecated: Use `services[_].tls.ca_cert` instead
    public let caCert: String?
    /// Deprecated: Use `services[_].tls.system_ca_required` instead
    public let systemCARequired: Bool?

    public init(
        cert: String,
        privateKey: String,
        privateKeyPassphrase: String? = nil,
        caCert: String? = nil,
        systemCARequired: Bool? = nil
    ) {
        self.cert = cert
        self.privateKey = privateKey
        self.privateKeyPassphrase = privateKeyPassphrase
        self.caCert = caCert
        self.systemCARequired = systemCARequired
    }

    private enum CodingKeys: String, CodingKey {
        case cert
        case privateKey = "private_key"
        case privateKeyPassphrase = "private_key_passphrase"
        case caCert = "ca_cert"
        case systemCARequired = "system_ca_required"
    }
}

/// Uses an Azure Managed Identities token's access token for bearer authorization
public struct AzureManagedIdentitiesAuthPlugin: Codable {
    let endpoint: String
    let apiVersion: String
    let resource: String
    let objectID: String
    let clientID: String
    let miResID: String
    let useAppServiceMsi: Bool?

    enum CodingKeys: String, CodingKey {
        case endpoint
        case apiVersion = "api_version"
        case resource
        case objectID = "object_id"
        case clientID = "client_id"
        case miResID = "mi_res_id"
        case useAppServiceMsi = "use_app_service_msi"
    }

    public init(
        endpoint: String = "",
        apiVersion: String = "",
        resource: String = "",
        objectID: String,
        clientID: String,
        miResID: String,
        useAppServiceMsi: Bool? = nil
    ) {
        self.endpoint =
            if endpoint == "" {

            } else {

            }
        self.apiVersion = apiVersion
        self.resource = resource
        self.objectID = objectID
        self.clientID = clientID
        self.miResID = miResID
        self.useAppServiceMsi = useAppServiceMsi

        // if ap.Endpoint == "" {
        // 	identityEndpoint := os.Getenv("IDENTITY_ENDPOINT")
        // 	if identityEndpoint != "" {
        // 		ap.UseAppServiceMsi = true
        // 		ap.Endpoint = identityEndpoint
        // 	} else {
        // 		ap.Endpoint = azureIMDSEndpoint
        // 	}
        // }

        // if ap.Resource == "" {
        // 	ap.Resource = defaultResource
        // }

        // if ap.APIVersion == "" {
        // 	if ap.UseAppServiceMsi {
        // 		ap.APIVersion = defaultAPIVersionForAppServiceMsi
        // 	} else {
        // 		ap.APIVersion = defaultAPIVersion
        // 	}
        // }
    }
}

// MARK: - AnyCodable Helper

/// A type-erased Codable value for handling heterogeneous JSON structures
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues(\.value)
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable cannot decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable cannot encode value of type \(type(of: value))"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}
