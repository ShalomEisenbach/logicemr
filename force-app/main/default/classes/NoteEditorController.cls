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
    @AuraEnabled
    public String signedByName { get; set; }
    @AuraEnabled
    public Id addendumToId { get; set; }
  }

  public class NoteTemplateInfo {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String body { get; set; }
    @AuraEnabled
    public String category { get; set; }
    @AuraEnabled
    public String shortcut { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static List<NoteTemplateInfo> getActiveTemplates() {
    List<NoteTemplateInfo> results = new List<NoteTemplateInfo>();
    for (NoteTemplate__c row : [
      SELECT Id, Name, Body__c, Category__c, Shortcut__c
      FROM NoteTemplate__c
      WHERE Active__c = TRUE
      ORDER BY Category__c, Name
    ]) {
      NoteTemplateInfo info = new NoteTemplateInfo();
      info.id = row.Id;
      info.name = row.Name;
      info.body = row.Body__c;
      info.category = row.Category__c;
      info.shortcut = row.Shortcut__c;
      results.add(info);
    }
    return results;
  }

  @AuraEnabled
  public static NoteEditorState getCurrentNote(Id encounterId) {
    List<NoteEditorState> notes = getNotes(encounterId);
    if (notes.isEmpty()) {
      return emptyState(requireEncounter(encounterId));
    }
    for (NoteEditorState note : notes) {
      if (STATUS_DRAFT.equals(note.status)) {
        return note;
      }
    }
    return notes[0];
  }

  @AuraEnabled
  public static List<NoteEditorState> getNotes(Id encounterId) {
    Encounter__c encounter = requireEncounter(encounterId);
    List<NoteEditorState> results = new List<NoteEditorState>();
    for (ClinicalNote__c note : [
      SELECT
        Id,
        Encounter__c,
        Patient__c,
        Note_Type__c,
        Body__c,
        Status__c,
        Signed_Date__c,
        Signed_By__r.Name,
        Addendum_To__c
      FROM ClinicalNote__c
      WHERE Encounter__c = :encounter.Id
      ORDER BY LastModifiedDate DESC, CreatedDate DESC, Id DESC
    ]) {
      results.add(toState(note));
    }
    return results;
  }

  @AuraEnabled
  public static NoteEditorState saveDraft(
    Id encounterId,
    Id noteId,
    String noteType,
    String body
  ) {
    return persistNote(encounterId, noteId, noteType, body, false);
  }

  @AuraEnabled
  public static NoteEditorState signNote(
    Id encounterId,
    Id noteId,
    String noteType,
    String body
  ) {
    return persistNote(encounterId, noteId, noteType, body, true);
  }

  @AuraEnabled
  public static NoteEditorState createAddendum(
    Id signedNoteId,
    String body,
    Boolean sign
  ) {
    requireNoteAccess(
      true,
      new List<Schema.SObjectField>{
        ClinicalNote__c.Patient__c,
        ClinicalNote__c.Encounter__c,
        ClinicalNote__c.Note_Type__c,
        ClinicalNote__c.Body__c,
        ClinicalNote__c.Status__c,
        ClinicalNote__c.Addendum_To__c
      }
    );
    if (signedNoteId == null) {
      throw new AuraHandledException('A signed note is required.');
    }
    List<ClinicalNote__c> parents = [
      SELECT Id, Patient__c, Encounter__c, Note_Type__c, Status__c
      FROM ClinicalNote__c
      WHERE Id = :signedNoteId
      LIMIT 1
    ];
    if (parents.isEmpty() || parents[0].Status__c != STATUS_SIGNED) {
      throw new AuraHandledException('Addenda must refer to a signed note.');
    }
    ClinicalNote__c parent = parents[0];
    ClinicalNote__c addendum = new ClinicalNote__c(
      Patient__c = parent.Patient__c,
      Encounter__c = parent.Encounter__c,
      Note_Type__c = parent.Note_Type__c,
      Body__c = body,
      Addendum_To__c = parent.Id,
      Status__c = sign == true ? STATUS_SIGNED : STATUS_DRAFT
    );
    assignCurrentAuthor(addendum, true);
    insert as user addendum;
    return toState(
      [
        SELECT
          Id,
          Patient__c,
          Encounter__c,
          Note_Type__c,
          Body__c,
          Status__c,
          Signed_Date__c,
          Signed_By__r.Name,
          Addendum_To__c
        FROM ClinicalNote__c
        WHERE Id = :addendum.Id
      ]
    );
  }

  private static NoteEditorState persistNote(
    Id encounterId,
    Id noteId,
    String noteType,
    String body,
    Boolean sign
  ) {
    Boolean creating = noteId == null;
    List<Schema.SObjectField> writtenFields = new List<Schema.SObjectField>{
      ClinicalNote__c.Note_Type__c,
      ClinicalNote__c.Body__c,
      ClinicalNote__c.Status__c
    };
    if (creating) {
      writtenFields.add(ClinicalNote__c.Patient__c);
      writtenFields.add(ClinicalNote__c.Encounter__c);
    }
    requireNoteAccess(creating, writtenFields);
    Encounter__c encounter = requireEncounter(encounterId);
    String resolvedType = resolveNoteType(noteType);
    ClinicalNote__c note;
    if (creating) {
      note = new ClinicalNote__c(
        Patient__c = encounter.Patient__c,
        Encounter__c = encounter.Id
      );
      assignCurrentAuthor(note, true);
    } else {
      ClinicalNote__c existing = requireEditableNote(noteId, encounter.Id);
      // Only write the fields this endpoint changes; ownership and signatures are retained.
      note = new ClinicalNote__c(Id = existing.Id);
      if (existing.Author__c == null) {
        assignCurrentAuthor(note, false);
      }
    }
    note.Note_Type__c = resolvedType;
    note.Body__c = body;
    note.Status__c = sign ? STATUS_SIGNED : STATUS_DRAFT;
    // User-mode DML enforces record access; the trigger stamps signature provenance.
    if (creating) {
      insert as user note;
    } else {
      update as user note;
    }
    return toState(
      [
        SELECT
          Id,
          Encounter__c,
          Patient__c,
          Note_Type__c,
          Body__c,
          Status__c,
          Signed_Date__c,
          Signed_By__r.Name,
          Addendum_To__c
        FROM ClinicalNote__c
        WHERE Id = :note.Id
        LIMIT 1
      ]
    );
  }

  private static void assignCurrentAuthor(
    ClinicalNote__c note,
    Boolean creating
  ) {
    Id authorId = currentPractitionerId();
    if (authorId == null)
      return;
    requireNoteAccess(
      creating,
      new List<Schema.SObjectField>{ ClinicalNote__c.Author__c }
    );
    note.Author__c = authorId;
  }

  private static void requireNoteAccess(
    Boolean creating,
    List<Schema.SObjectField> writtenFields
  ) {
    Schema.DescribeSObjectResult description = ClinicalNote__c.SObjectType.getDescribe();
    if (creating ? !description.isCreateable() : !description.isUpdateable()) {
      throw new AuraHandledException(
        'You do not have permission to save clinical notes.'
      );
    }
    for (Schema.SObjectField token : writtenFields) {
      Schema.DescribeFieldResult field = token.getDescribe();
      if (creating ? !field.isCreateable() : !field.isUpdateable()) {
        throw new AuraHandledException(
          'You do not have permission to save clinical note details.'
        );
      }
    }
  }

  private static ClinicalNote__c requireEditableNote(
    Id noteId,
    Id encounterId
  ) {
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
      throw new AuraHandledException(
        'Clinical note does not belong to this encounter.'
      );
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
    state.noteType = String.isBlank(note.Note_Type__c)
      ? DEFAULT_NOTE_TYPE
      : note.Note_Type__c;
    state.body = note.Body__c;
    state.status = note.Status__c;
    state.signedDate = note.Signed_Date__c;
    state.signedByName = note.Signed_By__r == null
      ? null
      : note.Signed_By__r.Name;
    state.addendumToId = note.Addendum_To__c;
    return state;
  }
}
