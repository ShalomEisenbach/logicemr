public interface EligibilityProvider {
    EligibilityResult check(EligibilityRequest req);
    List<EligibilityPayerMatch> searchPayers(String query);
}
