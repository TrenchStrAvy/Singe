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
