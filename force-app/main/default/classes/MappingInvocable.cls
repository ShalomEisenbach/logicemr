global with sharing class MappingInvocable {
    @InvocableMethod(
        label='Map Records to Patient'
        description='Maps each source record to a Patient using a Mapping Definition. Grouped by mapping and executed in one engine call per mapping.'
        category='LogicEMR'
    )
    global static List<Result> mapRecords(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<String> mappingNames = new Set<String>();
        for (Request request : requests) {
            if (request != null && request.mappingDefinitionId == null && String.isNotBlank(request.mappingName)) {
                mappingNames.add(request.mappingName);
            }
        }
        Map<String, Id> definitionIdByName = resolveDefinitionIdsByName(mappingNames);

        Map<Id, Set<Id>> sourceIdsByDefinition = new Map<Id, Set<Id>>();
        Map<Id, List<Integer>> resultIndexesByDefinition = new Map<Id, List<Integer>>();

        for (Integer i = 0; i < requests.size(); i++) {
            Result result = new Result();
            Request request = requests[i];
            results.add(result);
            if (request == null) {
                result.success = false;
                result.errorMessage = 'Request is required.';
                continue;
            }
            result.sourceRecordId = request.sourceRecordId;
            if (request.sourceRecordId == null) {
                result.success = false;
                result.errorMessage = 'Source Record Id is required.';
                continue;
            }

            Id definitionId = request.mappingDefinitionId;
            if (definitionId == null && String.isNotBlank(request.mappingName)) {
                definitionId = definitionIdByName.get(request.mappingName);
            }
            if (definitionId == null) {
                result.success = false;
                result.errorMessage = String.isBlank(request.mappingName)
                    ? 'Mapping Definition Id or Mapping Name is required.'
                    : 'No Mapping Definition named "' + request.mappingName + '" was found.';
                continue;
            }

            if (!sourceIdsByDefinition.containsKey(definitionId)) {
                sourceIdsByDefinition.put(definitionId, new Set<Id>());
                resultIndexesByDefinition.put(definitionId, new List<Integer>());
            }
            sourceIdsByDefinition.get(definitionId).add(request.sourceRecordId);
            resultIndexesByDefinition.get(definitionId).add(i);
        }

        MappingEngine engine = new MappingEngine();
        for (Id definitionId : sourceIdsByDefinition.keySet()) {
            MappingEngine.MappingResult engineResult = engine.run(
                definitionId,
                sourceIdsByDefinition.get(definitionId),
                false
            );
            applyEngineResult(results, resultIndexesByDefinition.get(definitionId), engineResult);
        }
        return results;
    }

    private static Map<String, Id> resolveDefinitionIdsByName(Set<String> mappingNames) {
        Map<String, Id> definitionIdByName = new Map<String, Id>();
        if (mappingNames.isEmpty()) {
            return definitionIdByName;
        }
        for (Mapping_Definition__c definition : [
            SELECT Id, Name, Active__c
            FROM Mapping_Definition__c
            WHERE Name IN :mappingNames
        ]) {
            if (!definitionIdByName.containsKey(definition.Name) || definition.Active__c == true) {
                definitionIdByName.put(definition.Name, definition.Id);
            }
        }
        return definitionIdByName;
    }

    private static void applyEngineResult(
        List<Result> results,
        List<Integer> indexes,
        MappingEngine.MappingResult engineResult
    ) {
        Map<Id, String> errorBySourceId = new Map<Id, String>();
        String groupError;
        for (MappingEngine.RowError rowError : engineResult.errors) {
            if (rowError.sourceRecordId == null) {
                groupError = rowError.message;
            } else {
                errorBySourceId.put(rowError.sourceRecordId, rowError.message);
            }
        }

        for (Integer index : indexes) {
            Result result = results[index];
            result.created = engineResult.created;
            result.updated = engineResult.updated;
            result.skipped = engineResult.skipped;
            if (groupError != null) {
                result.success = false;
                result.errorMessage = groupError;
            } else if (errorBySourceId.containsKey(result.sourceRecordId)) {
                result.success = false;
                result.errorMessage = errorBySourceId.get(result.sourceRecordId);
            } else {
                result.success = true;
            }
        }
    }

    global class Request {
        @InvocableVariable(label='Mapping Definition Id')
        global Id mappingDefinitionId;

        @InvocableVariable(label='Mapping Name')
        global String mappingName;

        @InvocableVariable(required=true label='Source Record Id')
        global Id sourceRecordId;
    }

    global class Result {
        @InvocableVariable(label='Source Record Id')
        global Id sourceRecordId;

        @InvocableVariable(label='Success')
        global Boolean success;

        @InvocableVariable(label='Error Message')
        global String errorMessage;

        @InvocableVariable(label='Created')
        global Integer created;

        @InvocableVariable(label='Updated')
        global Integer updated;

        @InvocableVariable(label='Skipped')
        global Integer skipped;
    }
}
