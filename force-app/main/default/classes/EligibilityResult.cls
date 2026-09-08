public with sharing class EligibilityResult {
    public Id eligibilityCheckId;
    public String status;
    public String plan;
    public Decimal copay;
    public Decimal coinsurance;
    public Decimal deductible;
    public Decimal deductibleRemaining;
    public Decimal oop;
    public String rawResponse;
    public String error;
}
