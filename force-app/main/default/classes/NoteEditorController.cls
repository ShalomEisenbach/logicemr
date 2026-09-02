public with sharing class NoteEditorController {
    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_SIGNED = 'Signed';
    private static final String DEFAULT_NOTE_TYPE = 'Progress Note';
    private static final Set<String> NOTE_TYPES = new Set<String>{
        'Progress Note',
        'H&P',
        'Discharge Summary',
        'Consult',
        'Other'
    };

    public class NoteEditorState {
        @AuraEnabled
        public Id noteId { get; set; }
        @AuraEnabled
        public Id encounterId { get; set; }
        @AuraEnabled
        public Id patientId { get; set; }
        @AuraEnabled
        public String noteType { get; set; }
        @AuraEnabled
        public String body { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public Datetime signedDate { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<NoteTemplate__c> getActiveTemplates() {
        return [
            SELECT Id, Name, Body__c, Category__c, Shortcut__c
            FROM NoteTemplate__c
            WHERE Active__c = TRUE
            ORDER BY Category__c, Name
        ];
    }

    @AuraEnabled
    public static NoteEditorState getCurrentNote(Id encounterId) {
        Encounter__c encounter = requireEncounter(encounterId);
        List<ClinicalNote__c> drafts = [
            SELECT
                Id,
                Encounter__c,
                Patient__c,
                Note_Type__c,
                Body__c,
                Status__c,
                Signed_Date__c
            FROM ClinicalNote__c
            WHERE Encounter__c = :encounter.Id AND Status__c = :STATUS_DRAFT
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (drafts.isEmpty()) {
            return emptyState(encounter);
        }
        return toState(drafts[0]);
    }

    @AuraEnabled
    public static NoteEditorState saveDraft(Id encounterId, Id noteId, String noteType, String body) {
        return persistNote(encounterId, noteId, noteType, body, false);
    }

    @AuraEnabled
    public static NoteEditorState signNote(Id encounterId, Id noteId, String noteType, String body) {
        return persistNote(encounterId, noteId, noteType, body, true);
    }

    private static NoteEditorState persistNote(
        Id encounterId,
        Id noteId,
        String noteType,
        String body,
        Boolean sign
    ) {
        Encounter__c encounter = requireEncounter(encounterId);
        String resolvedType = resolveNoteType(noteType);
        ClinicalNote__c note;
        if (noteId == null) {
            note = new ClinicalNote__c(
                Patient__c = encounter.Patient__c,
                Encounter__c = encounter.Id,
                Status__c = STATUS_DRAFT
            );
        } else {
            note = requireEditableNote(noteId, encounter.Id);
        }
        note.Note_Type__c = resolvedType;
        note.Body__c = body;
        if (note.Author__c == null) {
            note.Author__c = currentPractitionerId();
        }
        if (sign) {
            note.Status__c = STATUS_SIGNED;
            note.Signed_Date__c = Datetime.now();
        } else {
            note.Status__c = STATUS_DRAFT;
        }
        upsert note;
        return toState(
            [
                SELECT
                    Id,
                    Encounter__c,
                    Patient__c,
                    Note_Type__c,
                    Body__c,
                    Status__c,
                    Signed_Date__c
                FROM ClinicalNote__c
                WHERE Id = :note.Id
                LIMIT 1
            ]
        );
    }

    private static ClinicalNote__c requireEditableNote(Id noteId, Id encounterId) {
        List<ClinicalNote__c> notes = [
            SELECT
                Id,
                Encounter__c,
                Patient__c,
                Note_Type__c,
                Body__c,
                Status__c,
                Signed_Date__c,
                Author__c
            FROM ClinicalNote__c
            WHERE Id = :noteId
            LIMIT 1
        ];
        if (notes.isEmpty()) {
            throw new AuraHandledException('Clinical note was not found.');
        }
        ClinicalNote__c note = notes[0];
        if (note.Encounter__c != encounterId) {
            throw new AuraHandledException('Clinical note does not belong to this encounter.');
        }
        if (note.Status__c == STATUS_SIGNED) {
            throw new AuraHandledException('Signed notes cannot be edited.');
        }
        return note;
    }

    private static Encounter__c requireEncounter(Id encounterId) {
        if (encounterId == null) {
            throw new AuraHandledException('Encounter Id is required.');
        }
        List<Encounter__c> encounters = [
            SELECT Id, Patient__c
            FROM Encounter__c
            WHERE Id = :encounterId
            LIMIT 1
        ];
        if (encounters.isEmpty()) {
            throw new AuraHandledException('Encounter was not found.');
        }
        return encounters[0];
    }

    private static String resolveNoteType(String noteType) {
        if (String.isBlank(noteType)) {
            return DEFAULT_NOTE_TYPE;
        }
        if (!NOTE_TYPES.contains(noteType)) {
            throw new AuraHandledException('Note type is not valid.');
        }
        return noteType;
    }

    private static Id currentPractitionerId() {
        List<Practitioner__c> practitioners = [
            SELECT Id
            FROM Practitioner__c
            WHERE User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
        return practitioners.isEmpty() ? null : practitioners[0].Id;
    }

    private static NoteEditorState emptyState(Encounter__c encounter) {
        NoteEditorState state = new NoteEditorState();
        state.encounterId = encounter.Id;
        state.patientId = encounter.Patient__c;
        state.noteType = DEFAULT_NOTE_TYPE;
        state.body = '';
        state.status = STATUS_DRAFT;
        return state;
    }

    private static NoteEditorState toState(ClinicalNote__c note) {
        NoteEditorState state = new NoteEditorState();
        state.noteId = note.Id;
        state.encounterId = note.Encounter__c;
        state.patientId = note.Patient__c;
        state.noteType = String.isBlank(note.Note_Type__c) ? DEFAULT_NOTE_TYPE : note.Note_Type__c;
        state.body = note.Body__c;
        state.status = note.Status__c;
        state.signedDate = note.Signed_Date__c;
        return state;
    }
}
