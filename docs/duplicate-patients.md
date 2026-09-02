# Duplicate patient review

`emrDuplicatePatients` lists suspected duplicate `Patient__c` records for data stewards and admins. Detection is rule-based and deterministic: the same last name, first name, and date of birth (`GROUP BY Last_Name__c, First_Name__c, Date_of_Birth__c HAVING COUNT(Id) > 1`). There is no probabilistic or fuzzy matching.

`MRN__c` is a unique external Id, so two records cannot share an MRN. This panel targets the same-person-different-record case (identical demographics, different MRNs).

## Scope

This surfaces candidates for **manual review**. Open each record, compare the charts, and resolve by hand (correct demographics, inactivate a stray record, and so on).

**Record merge is out of scope.** Merge and automated dedupe are a separate, later effort.

## Access

Assign **LogicEMR Admin**, which grants the `LogicEMR_View_Data_Quality` custom permission and Apex access to `DuplicatePatientController`. The panel is hidden when the running user lacks that permission. `DuplicatePatientController` runs `with sharing`; users need visibility to the patient records they are reviewing.

The LogicEMR app Home page (`LogicEMR_Home`) places the panel in the sidebar. Clinicians using `LogicEMR Clinician` see the provider worklist and patient search; they do not receive `LogicEMR_View_Data_Quality`.

The panel caps the number of groups shown (50) and displays a “Showing first N groups” notice when more groups exist.
