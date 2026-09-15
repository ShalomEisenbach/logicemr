public class VendorNeutralClaim {
    public String schemaVersion { get; set; }
    public String sourceSystem { get; set; }
    public String claimType { get; set; }
    public Id sourceRecordId { get; set; }
    public String claimIdentifier { get; set; }
    public String status { get; set; }
    public Date dateOfService { get; set; }
    public String placeOfServiceCode { get; set; }
    public String claimFilingCode { get; set; }
    public Datetime readyAt { get; set; }
    public Decimal snapshotVersion { get; set; }
    public Datetime snapshotRefreshedAt { get; set; }
    public String currencyCode { get; set; }
    public Decimal totalCharge { get; set; }
    public Patient patient { get; set; }
    public Subscriber subscriber { get; set; }
    public Payer payer { get; set; }
    public RenderingProvider renderingProvider { get; set; }
    public BillingProvider billingProvider { get; set; }
    public List<Diagnosis> diagnoses { get; set; }
    public List<ServiceLine> serviceLines { get; set; }

    public class PersonName {
        public String first { get; set; }
        public String last { get; set; }
    }

    public class Address {
        public String street { get; set; }
        public String city { get; set; }
        public String state { get; set; }
        public String postalCode { get; set; }
        public String country { get; set; }
    }

    public class Patient {
        public PersonName name { get; set; }
        public Date dateOfBirth { get; set; }
        public String sex { get; set; }
        public Address address { get; set; }
    }

    public class Subscriber {
        public PersonName name { get; set; }
        public Date dateOfBirth { get; set; }
        public String sex { get; set; }
        public Address address { get; set; }
        public String patientRelationshipToSubscriber { get; set; }
        public String memberId { get; set; }
        public String groupNumber { get; set; }
        public Date coverageStart { get; set; }
        public Date coverageEnd { get; set; }
    }

    public class Payer {
        public String name { get; set; }
        public String identifier { get; set; }
    }

    public class RenderingProvider {
        public String name { get; set; }
        public String firstName { get; set; }
        public String lastName { get; set; }
        public String npi { get; set; }
        public String taxonomyCode { get; set; }
    }

    public class BillingProvider {
        public String legalName { get; set; }
        public String npi { get; set; }
        public String taxIdentifier { get; set; }
        public String taxonomyCode { get; set; }
        public Address address { get; set; }
    }

    public class Diagnosis {
        public Integer sequence { get; set; }
        public String type { get; set; }
        public String codeSystem { get; set; }
        public String code { get; set; }
        public String display { get; set; }
    }

    public class ServiceLine {
        public Id sourceLineId { get; set; }
        public String codeSystem { get; set; }
        public String code { get; set; }
        public String display { get; set; }
        public Date serviceDate { get; set; }
        public Decimal units { get; set; }
        public Decimal chargeAmount { get; set; }
        public List<String> modifiers { get; set; }
        public List<Integer> diagnosisPointers { get; set; }
        public Rate rate { get; set; }
    }

    public class Rate {
        public Decimal unitRate { get; set; }
        public String source { get; set; }
        public Boolean overridden { get; set; }
        public String overrideReason { get; set; }
    }
}
