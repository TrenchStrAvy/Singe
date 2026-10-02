import Foundation

/// A small curated glossary for professional terms Wiktionary lacks or under-ranks
/// (EU regulation, ICT risk, security). It sits beside Wiktionary, not instead of it;
/// the history ranking decides which reading comes first.
/// Format: term | headline | chip | topics | definition
enum Glossary {
    static let tsv = """
    RTS|Regulatory Technical Standards|EU law|eu regulation, finance, dora, law|Detailed EU rules drafted by the European Supervisory Authorities and adopted by the Commission that specify how parts of a regulation such as DORA or MiFID II must be applied.
    ITS|Implementing Technical Standards|EU law|eu regulation, finance, dora, law|EU rules drafted by the European Supervisory Authorities that set uniform conditions for applying a regulation, such as reporting templates, formats and procedures.
    RTS/ITS|Regulatory and Implementing Technical Standards|EU law|eu regulation, finance, dora, law|The two kinds of EU “Level 2” rules beneath a regulation such as DORA: RTS add technical substance, ITS fix uniform formats, templates and procedures.
    DORA|Digital Operational Resilience Act|EU law|eu regulation, finance, ict risk, dora|Regulation (EU) 2022/2554, applying since 17 January 2025, which sets uniform requirements for ICT risk management, incident reporting, resilience testing and third-party risk in the EU financial sector.
    TLPT|Threat-Led Penetration Testing|Security testing|dora, security, testing, ict risk|Advanced resilience testing that mimics the tactics of real threat actors against live production systems; required under DORA for significant financial entities, based on the TIBER-EU framework.
    TIBER-EU|Threat Intelligence-Based Ethical Red Teaming|Security testing|security, testing, dora, eu regulation|The ECB's European framework for intelligence-led red-team testing of financial entities, on which DORA's threat-led penetration testing builds.
    ESAs|European Supervisory Authorities|EU law|eu regulation, finance, supervision|The three EU financial supervisors: the European Banking Authority (EBA), the European Insurance and Occupational Pensions Authority (EIOPA) and the European Securities and Markets Authority (ESMA).
    ESA|European Supervisory Authority|EU law|eu regulation, finance, supervision|One of the three EU financial supervisors: EBA, EIOPA or ESMA.
    EBA|European Banking Authority|EU law|eu regulation, finance, banking, supervision|The EU agency that works on prudential regulation and supervision of banks across the EU.
    EIOPA|European Insurance and Occupational Pensions Authority|EU law|eu regulation, finance, insurance, supervision|The EU agency that supervises the insurance and occupational pensions sectors.
    ESMA|European Securities and Markets Authority|EU law|eu regulation, finance, markets, supervision|The EU agency that safeguards the stability of financial markets and supervises securities markets.
    CTPP|Critical ICT Third-Party Service Provider|DORA|dora, ict risk, third party risk, outsourcing|An ICT provider (such as a large cloud provider) designated under DORA as critical to the EU financial sector and directly overseen by a Lead Overseer from the ESAs.
    ICT|Information and Communication Technology|Technology|technology, computing, ict risk|The hardware, software, networks and services used to create, store, process and transmit information.
    ICT risk|ICT risk|Risk|ict risk, dora, risk management, security|Any reasonably identifiable risk to the network and information systems that could compromise the availability, integrity, confidentiality or authenticity of data or services if it materialises.
    Concentration risk|Concentration risk|Risk|risk management, third party risk, dora, finance|The exposure that arises from relying heavily on a single provider, counterparty or sector, so that one failure can disrupt many services at once.
    Third-party risk|Third-party risk|Risk|risk management, third party risk, outsourcing, dora|The risk that a supplier or service provider fails, is breached, or underperforms in a way that harms the organisation relying on it.
    Register of information|Register of information|DORA|dora, third party risk, reporting, eu regulation|The register DORA requires financial entities to keep of all contractual arrangements with ICT third-party service providers, in a format set by an ITS.
    Lead Overseer|Lead Overseer|DORA|dora, supervision, third party risk|The ESA (EBA, EIOPA or ESMA) appointed under DORA to directly oversee a specific critical ICT third-party service provider.
    Major ICT-related incident|Major ICT-related incident|DORA|dora, incident reporting, ict risk|An ICT incident with a high adverse impact on a financial entity's critical functions; under DORA it must be classified and reported to the competent authority within set deadlines.
    Management body|Management body|Governance|governance, dora, eu regulation|The board or equivalent body ultimately responsible for an entity; under DORA it bears final responsibility for managing ICT risk.
    NIS2|Network and Information Security Directive 2|EU law|eu regulation, security, cybersecurity|Directive (EU) 2022/2555, which sets cybersecurity risk-management and incident-reporting duties for essential and important entities across many sectors.
    GDPR|General Data Protection Regulation|EU law|eu regulation, privacy, data protection, law|Regulation (EU) 2016/679, the EU's law on the protection of personal data and the free movement of such data.
    DPO|Data Protection Officer|Privacy|privacy, data protection, gdpr|The person an organisation appoints under the GDPR to monitor compliance, advise on data-protection duties and act as the contact point for the supervisory authority.
    DPIA|Data Protection Impact Assessment|Privacy|privacy, data protection, gdpr, risk management|An assessment the GDPR requires before processing that is likely to pose a high risk to people's rights and freedoms.
    MiFID II|Markets in Financial Instruments Directive II|EU law|eu regulation, finance, markets|Directive 2014/65/EU, which regulates investment services and trading venues in the EU.
    CRR|Capital Requirements Regulation|EU law|eu regulation, finance, banking|Regulation (EU) No 575/2013, which sets prudential capital, liquidity and leverage requirements for banks.
    BCP|Business Continuity Plan|Risk|risk management, continuity, resilience|A documented plan for keeping critical business functions running during and after a disruption.
    BIA|Business Impact Analysis|Risk|risk management, continuity, resilience|An analysis of how disruption of each business function would affect the organisation over time, used to set recovery priorities.
    RTO|Recovery Time Objective|Resilience|risk management, continuity, resilience|The maximum acceptable time to restore a service or function after a disruption.
    RPO|Recovery Point Objective|Resilience|risk management, continuity, resilience|The maximum acceptable amount of data loss after a disruption, measured as time since the last recoverable copy.
    SIEM|Security Information and Event Management|Security|security, cybersecurity, monitoring|A system that collects and correlates security logs and events from across an organisation to detect and investigate threats.
    SOC|Security Operations Centre|Security|security, cybersecurity, monitoring|The team and facility that continuously monitors, detects and responds to security incidents.
    MFA|Multi-Factor Authentication|Security|security, cybersecurity, identity|Sign-in that requires two or more independent proofs of identity, such as a password plus a code from a device.
    IAM|Identity and Access Management|Security|security, cybersecurity, identity|The policies and tools that control who can access which systems and data.
    CIA triad|Confidentiality, Integrity, Availability|Security|security, cybersecurity, information security|The three core goals of information security: keeping data secret from the unauthorised, accurate and unaltered, and accessible when needed.
    ISMS|Information Security Management System|Security|security, iso 27001, governance|A systematic set of policies, processes and controls for managing information security risk, as specified by ISO/IEC 27001.
    ISO 27001|ISO/IEC 27001|Standard|security, iso 27001, governance, standards|The international standard that specifies requirements for establishing, running and improving an information security management system.
    GRC|Governance, Risk and Compliance|Governance|governance, risk management, compliance|The combined discipline of directing an organisation, managing its risks and meeting its legal and regulatory obligations.
    KRI|Key Risk Indicator|Risk|risk management, metrics|A metric that signals rising exposure to a specific risk, used for early warning.
    KPI|Key Performance Indicator|Management|management, metrics|A metric that measures how well an organisation or process meets a key objective.
    RCSA|Risk and Control Self-Assessment|Risk|risk management, operational risk, controls|A process in which business units identify their own risks and evaluate how well their controls work.
    Risk appetite|Risk appetite|Risk|risk management, governance|The amount and type of risk an organisation is willing to accept in pursuit of its objectives.
    Risk tolerance|Risk tolerance|Risk|risk management, governance|The acceptable variation around the risk appetite for a specific risk or objective.
    Three lines of defence|Three lines of defence|Governance|governance, risk management, internal audit|A governance model separating risk ownership (business), oversight (risk and compliance functions) and independent assurance (internal audit).
    Operational resilience|Operational resilience|Resilience|resilience, risk management, dora|The ability of an organisation to deliver critical operations through disruption: to prevent, adapt to, respond to and recover from it.
    Outsourcing|Outsourcing|Third parties|third party risk, outsourcing, risk management|Having an external provider perform a function or service the organisation would otherwise perform itself.
    Exit strategy|Exit strategy|Third parties|third party risk, outsourcing, dora|A documented plan for leaving a provider and moving a service elsewhere or in-house without unacceptable disruption; required by DORA for critical ICT services.
    CERT|Computer Emergency Response Team|Security|security, cybersecurity, incident response|A team that handles computer security incidents and coordinates responses.
    CSIRT|Computer Security Incident Response Team|Security|security, cybersecurity, incident response|A team that receives, analyses and responds to computer security incidents.
    IBITGQ|International Board for IT Governance Qualifications|Certification|certification, governance, security|An independent body that accredits IT governance, cybersecurity and data-protection qualifications.
    GASQ|Global Association for Software Quality|Certification|certification, quality, software|An independent certification body that runs examinations for software-quality and IT qualifications.
    Level 2|Level 2 measures|EU law|eu regulation, law, finance|In EU financial law, the detailed technical rules (RTS, ITS and delegated acts) adopted under a Level 1 regulation or directive.
    Level 1|Level 1 legislation|EU law|eu regulation, law, finance|In EU financial law, the framework regulation or directive adopted by the European Parliament and the Council.
    Delegated act|Delegated act|EU law|eu regulation, law|A non-legislative act adopted by the European Commission to supplement or amend non-essential parts of an EU law.
    Competent authority|Competent authority|Supervision|supervision, eu regulation, finance|The national body designated to supervise compliance with a regulation, for example a financial regulator.
    Hyper-V|Microsoft Hyper-V|Virtualization|virtualization, computing, microsoft, hypervisor|Microsoft's Type 1 hypervisor, built into Windows and Windows Server, that runs virtual machines directly on the hardware.
    VMware ESXi|VMware ESXi|Virtualization|virtualization, computing, hypervisor|VMware's bare-metal (Type 1) hypervisor for running virtual machines on servers.
    VirtualBox|Oracle VirtualBox|Virtualization|virtualization, computing, hypervisor|A free Type 2 hypervisor from Oracle that runs virtual machines on top of a desktop operating system.
    KVM|Kernel-based Virtual Machine|Virtualization|virtualization, computing, linux, hypervisor|The virtualization module built into the Linux kernel that turns Linux into a Type 1 hypervisor. Also short for a keyboard, video and mouse switch.
    Type 1 hypervisor|Type 1 (bare-metal) hypervisor|Virtualization|virtualization, computing, hypervisor|A hypervisor that runs directly on the hardware without a host operating system, such as Hyper-V, ESXi or KVM.
    Type 2 hypervisor|Type 2 (hosted) hypervisor|Virtualization|virtualization, computing, hypervisor|A hypervisor that runs as an application on a host operating system, such as VirtualBox or VMware Workstation.
    VM escape|Virtual machine escape|Security|security, virtualization, cybersecurity|An attack in which code inside a virtual machine breaks out to interact with the hypervisor or other virtual machines on the same host.
    VM sprawl|Virtual machine sprawl|Virtualization|virtualization, security, management|An uncontrolled growth of virtual machines that are no longer tracked, patched or needed, which increases cost and attack surface.
    Container|Container|Cloud|cloud, virtualization, devops|A lightweight, isolated package of an application and its dependencies that shares the host operating system's kernel instead of running a full guest OS.
    Docker|Docker|Cloud|cloud, containers, devops|A widely used platform for building, shipping and running applications in containers.
    Kubernetes|Kubernetes|Cloud|cloud, containers, devops|An open-source system for deploying, scaling and managing containerised applications across clusters of machines.
    Serverless|Serverless computing|Cloud|cloud, computing, devops|A cloud model in which the provider runs code on demand and manages the servers, so you pay only for execution time.
    IaaS|Infrastructure as a Service|Cloud|cloud, computing|A cloud model that rents out virtualised computing resources such as servers, storage and networks; the customer manages the operating systems and applications.
    PaaS|Platform as a Service|Cloud|cloud, computing|A cloud model that provides a managed platform for building and running applications without managing the underlying infrastructure.
    SaaS|Software as a Service|Cloud|cloud, computing|A cloud model in which complete applications are delivered over the internet and managed by the provider.
    CASB|Cloud Access Security Broker|Security|security, cloud, cybersecurity|A security control point between users and cloud services that enforces policies such as visibility, data protection and threat protection.
    SASE|Secure Access Service Edge|Security|security, networking, cloud|A cloud-delivered architecture that combines networking (such as SD-WAN) with security services like secure web gateways, CASB and Zero Trust access.
    SD-WAN|Software-Defined Wide Area Network|Networking|networking, cloud|A WAN architecture that uses software to route traffic across multiple connection types, such as broadband, LTE and MPLS.
    Zero Trust|Zero Trust|Security|security, cybersecurity, architecture|A security model that trusts no user or device by default and verifies every access request, regardless of where it comes from.
    BitLocker|BitLocker|Security|security, encryption, microsoft|Microsoft's full-disk encryption feature for Windows, usually paired with the TPM.
    FileVault|FileVault|Security|security, encryption, apple|Apple's full-disk encryption for macOS.
    TPM|Trusted Platform Module|Security|security, encryption, hardware|A dedicated chip on the motherboard that securely stores cryptographic keys and supports features such as secure boot and disk encryption.
    HSM|Hardware Security Module|Security|security, encryption, hardware|A tamper-resistant device that generates, stores and uses cryptographic keys for high-security operations.
    Active Directory|Microsoft Active Directory|Identity|security, identity, microsoft|Microsoft's directory service for Windows networks that stores users, groups and computers and handles authentication and authorisation.
    LDAP|Lightweight Directory Access Protocol|Identity|security, identity, networking, protocol|A protocol for reading and editing directory services such as Active Directory, typically over port 389 (or 636 for LDAPS).
    RADIUS|Remote Authentication Dial-In User Service|Identity|security, identity, networking, protocol|A protocol for centralised authentication, authorisation and accounting (AAA) of users connecting to a network, often used for Wi-Fi and VPN.
    TACACS+|Terminal Access Controller Access-Control System Plus|Identity|security, identity, networking, protocol|A Cisco-developed AAA protocol that encrypts the full payload and separates authentication, authorisation and accounting; commonly used for administering network devices.
    SAML|Security Assertion Markup Language|Identity|security, identity, protocol|An XML-based standard for exchanging authentication and authorisation data between an identity provider and a service provider, used for single sign-on.
    OAuth|OAuth|Identity|security, identity, protocol|An authorisation framework that lets an application access a user's resources on another service without receiving the user's password.
    OpenID Connect|OpenID Connect|Identity|security, identity, protocol|An authentication layer built on OAuth 2.0 that lets applications verify who a user is.
    SSO|Single Sign-On|Identity|security, identity|An arrangement in which one login gives a user access to several separate systems.
    AAA|Authentication, Authorisation and Accounting|Identity|security, identity|The framework of verifying who a user is, deciding what they may do, and recording what they did.
    RBAC|Role-Based Access Control|Identity|security, identity, access control|Access control that grants permissions according to a user's role in the organisation.
    ABAC|Attribute-Based Access Control|Identity|security, identity, access control|Access control that decides access by evaluating attributes of the user, resource, action and environment.
    Least privilege|Principle of least privilege|Security|security, access control|Giving users and systems only the minimum access they need to do their job.
    Separation of duties|Separation of duties|Security|security, governance, access control|Splitting critical tasks among different people so that no single person can complete them alone, reducing fraud and errors.
    Non-repudiation|Non-repudiation|Security|security, cryptography|Assurance that someone cannot deny having performed an action, such as sending a message, typically provided by digital signatures.
    PKI|Public Key Infrastructure|Cryptography|security, cryptography, certificates|The roles, policies and systems that create, manage, distribute and revoke digital certificates and public keys.
    CRL|Certificate Revocation List|Cryptography|security, cryptography, certificates|A list, published by a certificate authority, of certificates revoked before their expiry date.
    OCSP|Online Certificate Status Protocol|Cryptography|security, cryptography, certificates|A protocol for checking in real time whether a single digital certificate has been revoked.
    AES|Advanced Encryption Standard|Cryptography|security, cryptography, encryption|The widely used symmetric block cipher, with 128-, 192- or 256-bit keys.
    RSA|RSA|Cryptography|security, cryptography, encryption|An asymmetric public-key algorithm used for encryption and digital signatures, named after Rivest, Shamir and Adleman.
    ECC|Elliptic Curve Cryptography|Cryptography|security, cryptography, encryption|Public-key cryptography based on elliptic curves, giving security comparable to RSA with much smaller keys.
    Diffie-Hellman|Diffie-Hellman key exchange|Cryptography|security, cryptography|A method that lets two parties agree on a shared secret key over an insecure channel.
    HMAC|Hash-based Message Authentication Code|Cryptography|security, cryptography, integrity|A code built from a cryptographic hash and a secret key that verifies both the integrity and the authenticity of a message.
    Salting|Salting|Cryptography|security, cryptography, passwords|Adding a unique random value to each password before hashing so that identical passwords produce different hashes and precomputed attacks fail.
    Key stretching|Key stretching|Cryptography|security, cryptography, passwords|Making a weak key or password harder to brute-force by running it through many hashing rounds, as in PBKDF2, bcrypt or Argon2.
    IPsec|Internet Protocol Security|Networking|security, networking, protocol, vpn|A suite of protocols that authenticates and encrypts IP packets, commonly used for site-to-site and remote-access VPNs.
    802.1X|IEEE 802.1X|Networking|security, networking, access control|A port-based network access control standard that requires devices to authenticate (usually through RADIUS) before they may use a wired or wireless network.
    WPA3|Wi-Fi Protected Access 3|Networking|security, networking, wireless|The current Wi-Fi security standard, which replaces WPA2's pre-shared key exchange with SAE for stronger protection against password guessing.
    DNSSEC|Domain Name System Security Extensions|Networking|security, networking, dns|Extensions that digitally sign DNS records so that resolvers can verify they have not been forged.
    SPF|Sender Policy Framework|Email security|security, email, dns|A DNS record that lists which mail servers are allowed to send email for a domain.
    DKIM|DomainKeys Identified Mail|Email security|security, email, dns|An email authentication method that adds a digital signature so receivers can verify a message came from the domain and was not altered.
    DMARC|Domain-based Message Authentication, Reporting and Conformance|Email security|security, email, dns|A policy, published in DNS, that tells receivers what to do with mail failing SPF or DKIM checks and where to send reports.
    IDS|Intrusion Detection System|Security|security, networking, monitoring|A system that monitors network or host activity for malicious behaviour and raises alerts.
    IPS|Intrusion Prevention System|Security|security, networking, monitoring|A system that monitors traffic like an IDS but can also block malicious activity in real time.
    WAF|Web Application Firewall|Security|security, web, networking|A firewall that filters HTTP traffic to and from a web application to block attacks such as SQL injection and cross-site scripting.
    NAC|Network Access Control|Security|security, networking, access control|Technology that checks the identity and security posture of devices before letting them onto a network.
    EDR|Endpoint Detection and Response|Security|security, endpoint, monitoring|Software that continuously monitors endpoints, detects suspicious activity and helps investigate and respond to it.
    XDR|Extended Detection and Response|Security|security, monitoring|Detection and response that correlates data across endpoints, network, cloud and email in one platform.
    SOAR|Security Orchestration, Automation and Response|Security|security, monitoring, automation|Tools that automate and coordinate security workflows and incident response across different systems.
    DLP|Data Loss Prevention|Security|security, data protection|Tools and policies that detect and prevent sensitive data from leaving the organisation without authorisation.
    MDM|Mobile Device Management|Security|security, endpoint, mobile|Software that lets an organisation enrol, configure, secure and wipe mobile devices.
    BYOD|Bring Your Own Device|Security|security, mobile, policy|A policy that lets employees use their personal devices for work.
    COPE|Corporate-Owned, Personally Enabled|Security|security, mobile, policy|A deployment model in which the organisation owns the device but allows some personal use.
    CVE|Common Vulnerabilities and Exposures|Vulnerabilities|security, vulnerabilities|The public catalogue of disclosed security vulnerabilities, each with a unique identifier such as CVE-2024-12345.
    CVSS|Common Vulnerability Scoring System|Vulnerabilities|security, vulnerabilities, metrics|An open standard that rates the severity of vulnerabilities on a scale from 0 to 10.
    OWASP|Open Worldwide Application Security Project|Security|security, web, application security|A non-profit foundation known for its Top 10 list of the most critical web application security risks.
    XSS|Cross-Site Scripting|Attacks|security, web, attacks|An attack that injects malicious scripts into web pages viewed by other users.
    CSRF|Cross-Site Request Forgery|Attacks|security, web, attacks|An attack that tricks a logged-in user's browser into sending an unwanted request to a site that trusts them.
    SQL injection|SQL injection|Attacks|security, web, attacks, databases|An attack that inserts malicious SQL into an application's input to read or change its database.
    Buffer overflow|Buffer overflow|Attacks|security, attacks, software|Writing more data into a memory buffer than it can hold, which can crash a program or let an attacker run code.
    Smishing|Smishing|Attacks|security, social engineering, attacks|Phishing carried out through SMS text messages.
    Vishing|Vishing|Attacks|security, social engineering, attacks|Phishing carried out over voice calls.
    Pretexting|Pretexting|Attacks|security, social engineering, attacks|Social engineering in which the attacker invents a believable scenario to get the victim to share information or take an action.
    Tabletop exercise|Tabletop exercise|Resilience|security, incident response, resilience|A discussion-based exercise in which a team talks through its response to a simulated incident.
    Honeypot|Honeypot|Security|security, deception, monitoring|A decoy system set up to attract attackers so their methods can be observed and they are diverted from real systems.
    Sandboxing|Sandboxing|Security|security, malware|Running code in an isolated environment so it cannot affect the rest of the system.
    MITRE ATT&CK|MITRE ATT&CK|Threat intelligence|security, threat intelligence, frameworks|A public knowledge base of adversary tactics and techniques observed in real attacks.
    Cyber Kill Chain|Cyber Kill Chain|Threat intelligence|security, threat intelligence, frameworks|Lockheed Martin's model of the seven stages of a cyberattack, from reconnaissance to actions on objectives.
    STIX|Structured Threat Information Expression|Threat intelligence|security, threat intelligence|A standard language for describing cyber threat intelligence.
    TAXII|Trusted Automated Exchange of Intelligence Information|Threat intelligence|security, threat intelligence, protocol|A protocol for sharing threat intelligence, usually STIX data, over HTTPS.
    SLE|Single Loss Expectancy|Risk|risk management, security, metrics|The expected monetary loss from one occurrence of a risk: asset value × exposure factor.
    ARO|Annualised Rate of Occurrence|Risk|risk management, security, metrics|How many times a risk is expected to occur in a year.
    ALE|Annualised Loss Expectancy|Risk|risk management, security, metrics|The expected yearly loss from a risk: single loss expectancy × annualised rate of occurrence.
    MTTR|Mean Time To Repair|Resilience|resilience, risk management, metrics|The average time needed to repair a failed system and restore it to service.
    MTBF|Mean Time Between Failures|Resilience|resilience, risk management, metrics|The average operating time between failures of a repairable system.
    SLA|Service Level Agreement|Third parties|third party risk, contracts|A contract that defines the level of service a provider must deliver, such as uptime and response times.
    MOU|Memorandum of Understanding|Third parties|third party risk, contracts|A non-binding document describing an intended agreement and shared goals between parties.
    NDA|Non-Disclosure Agreement|Third parties|contracts, data protection|A contract in which parties agree to keep specified information confidential.
    SOW|Statement of Work|Third parties|contracts, third party risk|A document that defines the specific work, deliverables and timelines for a project or contract.
    """

    static func load() -> [String: [Sense]] {
        var out: [String: [Sense]] = [:]
        for (i, line) in tsv.split(separator: "\n").enumerated() {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count == 5 else { continue }
            let key = f[0].lowercased()
            let sense = Sense(id: "g:\(i)", term: f[0], name: f[1], gloss: f[4], label: f[2],
                              topics: f[3], rank: 0, source: .glossary)
            out[key, default: []].append(sense)
        }
        return out
    }
}
