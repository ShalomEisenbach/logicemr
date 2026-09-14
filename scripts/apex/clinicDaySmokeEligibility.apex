Id coverageId = 'a0Shm000000HIJtEAO';
Eligibility_Check__c check = EligibilityCheckController.runCheck(coverageId);

System.debug('PASS eligibility checkId=' + check.Id
             + ' status=' + check.Status__c
             + ' copay=' + check.Copay__c
             + ' deductible=' + check.Deductible__c
             + ' error=' + check.Error_Message__c);