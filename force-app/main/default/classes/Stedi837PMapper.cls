public class Stedi837PMapper {
    private static final Set<String> RESERVED_CHARACTERS = new Set<String>{ '~', '*', ':', '^', '>', '`' };

    public static String serialize(
        VendorNeutralClaim claim,
        ClaimSubmissionConfig config,
        String patientControlNumber
    ) {
        validate(claim, config, patientControlNumber);
        return JSON.serialize(buildPayload(claim, config, patientControlNumber));
    }

    @TestVisible
    private static Map<String, Object> buildPayload(
        VendorNeutralClaim claim,
        ClaimSubmissionConfig config,
        String patientControlNumber
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('usageIndicator', config.usageIndicator);
        payload.put('tradingPartnerServiceId', safe(claim.payer.identifier, 'payer identifier', 80));
        payload.put('tradingPartnerName', safe(claim.payer.name, 'payer name', 60));

        Map<String, Object> contact = new Map<String, Object>();
        contact.put('name', safe(config.contactName, 'submitter contact name', 60));
        contact.put('phoneNumber', config.contactPhone);
        Map<String, Object> submitter = new Map<String, Object>();
        submitter.put('organizationName', safe(config.submitterName, 'submitter name', 60));
        submitter.put('contactInformation', contact);
        if (String.isNotBlank(config.submitterIdentifier)) {
            submitter.put('submitterIdentification', safe(config.submitterIdentifier, 'submitter identifier', 80));
        }
        payload.put('submitter', submitter);
        payload.put('receiver', new Map<String, Object>{
            'organizationName' => safe(claim.payer.name, 'receiver name', 60)
        });
        payload.put('subscriber', subscriber(claim));
        if (claim.subscriber.patientRelationshipToSubscriber != 'Self') {
            payload.put('dependent', dependent(claim));
        }
        payload.put('billing', billing(claim));
        payload.put('claimInformation', claimInformation(claim, patientControlNumber));
        return payload;
    }

    private static Map<String, Object> subscriber(VendorNeutralClaim claim) {
        Map<String, Object> subscriber = new Map<String, Object>();
        subscriber.put('memberId', safe(claim.subscriber.memberId, 'subscriber member ID', 80));
        subscriber.put('paymentResponsibilityLevelCode', 'P');
        subscriber.put('subscriberGroupName', safe(claim.payer.name, 'subscriber group name', 60));
        subscriber.put('firstName', safe(claim.subscriber.name.first, 'subscriber first name', 35));
        subscriber.put('lastName', safe(claim.subscriber.name.last, 'subscriber last name', 60));
        if (String.isNotBlank(claim.subscriber.groupNumber)) {
            subscriber.put('groupNumber', safe(claim.subscriber.groupNumber, 'subscriber group number', 50));
        }
        if (claim.subscriber.patientRelationshipToSubscriber == 'Self') {
            subscriber.put('dateOfBirth', formatDate(claim.subscriber.dateOfBirth));
            subscriber.put('gender', gender(claim.subscriber.sex));
            subscriber.put('address', address(claim.subscriber.address));
        }
        return subscriber;
    }

    private static Map<String, Object> dependent(VendorNeutralClaim claim) {
        Map<String, Object> dependent = new Map<String, Object>();
        dependent.put('firstName', safe(claim.patient.name.first, 'patient first name', 35));
        dependent.put('lastName', safe(claim.patient.name.last, 'patient last name', 60));
        dependent.put('dateOfBirth', formatDate(claim.patient.dateOfBirth));
        dependent.put('gender', gender(claim.patient.sex));
        dependent.put('relationshipToSubscriberCode', relationshipCode(claim.subscriber.patientRelationshipToSubscriber));
        dependent.put('address', address(claim.patient.address));
        return dependent;
    }

    private static Map<String, Object> billing(VendorNeutralClaim claim) {
        return new Map<String, Object>{
            'npi' => safe(claim.billingProvider.npi, 'billing provider NPI', 10),
            'employerId' => safe(claim.billingProvider.taxIdentifier, 'billing provider EIN', 9),
            'taxonomyCode' => safe(claim.billingProvider.taxonomyCode, 'billing provider taxonomy', 10),
            'organizationName' => safe(claim.billingProvider.legalName, 'billing provider name', 60),
            'address' => address(claim.billingProvider.address)
        };
    }

    private static Map<String, Object> claimInformation(VendorNeutralClaim claim, String patientControlNumber) {
        Map<String, Object> info = new Map<String, Object>();
        info.put('claimFilingCode', safe(claim.claimFilingCode, 'claim filing code', 2));
        info.put('patientControlNumber', safe(patientControlNumber, 'patient control number', 17));
        info.put('claimChargeAmount', money(claim.totalCharge));
        info.put('placeOfServiceCode', safe(claim.placeOfServiceCode, 'place of service code', 2));
        info.put('claimFrequencyCode', '1');
        info.put('signatureIndicator', 'Y');
        info.put('planParticipationCode', 'A');
        info.put('benefitsAssignmentCertificationIndicator', 'Y');
        info.put('releaseInformationCode', 'Y');

        List<Object> diagnoses = new List<Object>();
        for (Integer i = 0; i < claim.diagnoses.size(); i++) {
            VendorNeutralClaim.Diagnosis diagnosis = claim.diagnoses[i];
            diagnoses.add(new Map<String, Object>{
                'diagnosisTypeCode' => i == 0 ? 'ABK' : 'ABF',
                'diagnosisCode' => safe(diagnosis.code.replace('.', ''), 'diagnosis code', 30)
            });
        }
        info.put('healthCareCodeInformation', diagnoses);
        info.put('serviceFacilityLocation', new Map<String, Object>{
            'organizationName' => safe(claim.billingProvider.legalName, 'service facility name', 60),
            'npi' => safe(claim.billingProvider.npi, 'service facility NPI', 10),
            'address' => address(claim.billingProvider.address)
        });

        List<Object> serviceLines = new List<Object>();
        for (VendorNeutralClaim.ServiceLine line : claim.serviceLines) {
            List<String> pointers = new List<String>();
            for (Integer pointer : line.diagnosisPointers) pointers.add(String.valueOf(pointer));
            Map<String, Object> professionalService = new Map<String, Object>();
            professionalService.put('procedureIdentifier', 'HC');
            professionalService.put('procedureCode', safe(line.code, 'procedure code', 48));
            professionalService.put('procedureModifiers', safeList(line.modifiers, 'procedure modifier', 2));
            professionalService.put('lineItemChargeAmount', money(line.chargeAmount));
            professionalService.put('measurementUnit', 'UN');
            professionalService.put('serviceUnitCount', String.valueOf(line.units));
            professionalService.put('compositeDiagnosisCodePointers', new Map<String, Object>{
                'diagnosisCodePointers' => pointers
            });
            Map<String, Object> rendering = new Map<String, Object>{
                'npi' => safe(claim.renderingProvider.npi, 'rendering provider NPI', 10),
                'taxonomyCode' => safe(claim.renderingProvider.taxonomyCode, 'rendering provider taxonomy', 10),
                'firstName' => safe(claim.renderingProvider.firstName, 'rendering provider first name', 35),
                'lastName' => safe(claim.renderingProvider.lastName, 'rendering provider last name', 60)
            };
            serviceLines.add(new Map<String, Object>{
                'serviceDate' => formatDate(line.serviceDate),
                'professionalService' => professionalService,
                'providerControlNumber' => lineControlNumber(line.sourceLineId),
                'renderingProvider' => rendering
            });
        }
        info.put('serviceLines', serviceLines);
        return info;
    }

    private static Map<String, Object> address(VendorNeutralClaim.Address source) {
        Map<String, Object> value = new Map<String, Object>();
        value.put('address1', safe(source.street, 'street address', 55));
        value.put('city', safe(source.city, 'city', 30));
        value.put('state', safe(source.state, 'state', 3));
        value.put('postalCode', safe(source.postalCode == null ? null : source.postalCode.replaceAll('[^A-Za-z0-9]', ''), 'postal code', 15));
        if (String.isNotBlank(source.country)) value.put('countryCode', safe(source.country, 'country code', 3));
        return value;
    }

    private static void validate(VendorNeutralClaim claim, ClaimSubmissionConfig config, String patientControlNumber) {
        if (claim == null) throw error('Canonical claim is required.');
        if (config == null) throw error('Claim submission configuration is required.');
        config.validate();
        if (claim.claimType != 'professional') throw error('Only professional claims can be submitted through the 837P adapter.');
        if (claim.payer == null || String.isBlank(claim.payer.identifier)) throw error('Payer identifier is required.');
        if (String.isBlank(claim.claimFilingCode)) throw error('Claim filing code is required.');
        if (String.isBlank(claim.placeOfServiceCode)) throw error('Place of service code is required.');
        if (claim.renderingProvider == null || String.isBlank(claim.renderingProvider.firstName) ||
            String.isBlank(claim.renderingProvider.lastName)) {
            throw error('Rendering provider first and last name snapshots are required.');
        }
        if (claim.billingProvider == null || claim.billingProvider.address == null) throw error('Billing provider is required.');
        if (claim.patient == null || claim.patient.name == null || claim.subscriber == null || claim.subscriber.name == null) {
            throw error('Patient and subscriber snapshots are required.');
        }
        if (claim.diagnoses == null || claim.diagnoses.isEmpty()) throw error('At least one diagnosis is required.');
        if (claim.serviceLines == null || claim.serviceLines.isEmpty()) throw error('At least one service line is required.');
        safe(patientControlNumber, 'patient control number', 17);
    }

    private static String safe(String value, String label, Integer maxLength) {
        if (String.isBlank(value)) throw error(label.capitalize() + ' is required.');
        String trimmed = value.trim();
        if (trimmed.length() > maxLength) throw error(label.capitalize() + ' exceeds ' + maxLength + ' characters.');
        for (String character : RESERVED_CHARACTERS) {
            if (trimmed.contains(character)) throw error(label.capitalize() + ' contains an X12 reserved character.');
        }
        return trimmed;
    }

    private static List<String> safeList(List<String> values, String label, Integer maxLength) {
        List<String> result = new List<String>();
        if (values == null) return result;
        for (String value : values) result.add(safe(value, label, maxLength));
        return result;
    }

    private static String relationshipCode(String relationship) {
        if (relationship == 'Spouse') return '01';
        if (relationship == 'Child') return '19';
        if (relationship == 'Other') return 'G8';
        throw error('Unsupported patient relationship to subscriber: ' + relationship + '.');
    }

    private static String gender(String value) {
        if (value == 'Male') return 'M';
        if (value == 'Female') return 'F';
        return 'U';
    }

    private static String formatDate(Date value) {
        if (value == null) throw error('A required claim date is missing.');
        return String.valueOf(value.year()) + pad(value.month()) + pad(value.day());
    }

    private static String pad(Integer value) {
        return value < 10 ? '0' + String.valueOf(value) : String.valueOf(value);
    }

    private static String money(Decimal value) {
        if (value == null || value <= 0) throw error('Claim amounts must be greater than zero.');
        return String.valueOf(value.setScale(2));
    }

    private static String lineControlNumber(Id sourceLineId) {
        String value = String.valueOf(sourceLineId);
        return value.length() <= 17 ? value : value.substring(0, 17);
    }

    private static ClaimSubmissionProviderFactory.ClaimSubmissionException error(String message) {
        return new ClaimSubmissionProviderFactory.ClaimSubmissionException(message);
    }
}
