public with sharing class PatientSearchController {
    private static final Integer MAX_RESULTS = 50;
    private static final Pattern FOUR_DIGIT_YEAR = Pattern.compile('^[0-9]{4}$');
    private static final Pattern ORDINAL = Pattern.compile('(?i)(\\d+)(st|nd|rd|th)\\b');
    private static final Map<String, Integer> MONTHS = new Map<String, Integer>{
        'january' => 1,
        'jan' => 1,
        'february' => 2,
        'feb' => 2,
        'march' => 3,
        'mar' => 3,
        'april' => 4,
        'apr' => 4,
        'may' => 5,
        'june' => 6,
        'jun' => 6,
        'july' => 7,
        'jul' => 7,
        'august' => 8,
        'aug' => 8,
        'september' => 9,
        'sep' => 9,
        'sept' => 9,
        'october' => 10,
        'oct' => 10,
        'november' => 11,
        'nov' => 11,
        'december' => 12,
        'dec' => 12
    };

    @AuraEnabled(cacheable=true)
    public static List<Patient__c> search(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return new List<Patient__c>();
        }

        String trimmed = searchTerm.trim();
        String likePattern = '%' + trimmed + '%';
        String digits = trimmed.replaceAll('[^0-9]', '');
        List<Date> candidateDates = parseCandidateDates(trimmed);
        Date rangeStart;
        Date rangeEnd;
        if (candidateDates.isEmpty()) {
            DateRange monthYear = parseMonthYear(trimmed);
            if (monthYear != null) {
                rangeStart = monthYear.startDate;
                rangeEnd = monthYear.endDate;
            } else if (FOUR_DIGIT_YEAR.matcher(trimmed).matches()) {
                Integer year = Integer.valueOf(trimmed);
                if (year >= 1800 && year <= 2100) {
                    rangeStart = Date.newInstance(year, 1, 1);
                    rangeEnd = Date.newInstance(year, 12, 31);
                }
            }
        }

        String digitsLike;
        String dashedPhoneLike;
        if (digits.length() >= 7) {
            digitsLike = '%' + digits + '%';
        }
        if (digits.length() == 10) {
            dashedPhoneLike =
                '%' +
                digits.substring(0, 3) +
                '-' +
                digits.substring(3, 6) +
                '-' +
                digits.substring(6) +
                '%';
        }

        String firstTokenLike;
        String secondTokenLike;
        List<String> tokens = trimmed.split('\\s+');
        if (tokens.size() == 2) {
            firstTokenLike = '%' + tokens[0] + '%';
            secondTokenLike = '%' + tokens[1] + '%';
        }

        List<String> filters = new List<String>{
            'Last_Name__c LIKE :likePattern',
            'First_Name__c LIKE :likePattern',
            'MRN__c LIKE :likePattern',
            'FHIR_Id__c LIKE :likePattern',
            'Source_System_Id__c LIKE :likePattern',
            'Phone__c LIKE :likePattern'
        };
        if (String.isNotBlank(digitsLike) && digitsLike != likePattern) {
            filters.add('Phone__c LIKE :digitsLike');
        }
        if (String.isNotBlank(dashedPhoneLike) && dashedPhoneLike != likePattern) {
            filters.add('Phone__c LIKE :dashedPhoneLike');
        }
        if (!candidateDates.isEmpty()) {
            filters.add('Date_of_Birth__c IN :candidateDates');
        }
        if (rangeStart != null && rangeEnd != null) {
            filters.add('(Date_of_Birth__c >= :rangeStart AND Date_of_Birth__c <= :rangeEnd)');
        }
        if (firstTokenLike != null && secondTokenLike != null) {
            filters.add('(First_Name__c LIKE :firstTokenLike AND Last_Name__c LIKE :secondTokenLike)');
            filters.add('(First_Name__c LIKE :secondTokenLike AND Last_Name__c LIKE :firstTokenLike)');
        }

        String soql =
            'SELECT Id, Last_Name__c, First_Name__c, MRN__c, Date_of_Birth__c, Phone__c, Status__c ' +
            'FROM Patient__c WHERE ' +
            String.join(filters, ' OR ') +
            ' ORDER BY Last_Name__c, First_Name__c, MRN__c LIMIT :MAX_RESULTS';
        return Database.query(soql);
    }

    private class DateRange {
        public Date startDate;
        public Date endDate;

        public DateRange(Date startDate, Date endDate) {
            this.startDate = startDate;
            this.endDate = endDate;
        }
    }

    private static List<Date> parseCandidateDates(String raw) {
        Set<Date> found = new Set<Date>();
        if (String.isBlank(raw)) {
            return new List<Date>();
        }

        String text = raw.trim();
        addNamedMonthDates(found, text);
        addSeparatedNumericDates(found, text);
        addCompactDigitDates(found, text.replaceAll('[^0-9]', ''));
        if (!isAllNumericTokens(text)) {
            try {
                found.add(Date.parse(text));
            } catch (Exception ignored) {
            }
        }
        try {
            found.add(Date.valueOf(text));
        } catch (Exception ignored) {
        }
        found.remove(null);
        return new List<Date>(found);
    }

    private static void addNamedMonthDates(Set<Date> found, String raw) {
        String cleaned = ORDINAL.matcher(raw.toLowerCase()).replaceAll('$1');
        List<String> parts = tokenize(cleaned);
        if (parts.size() != 3) {
            return;
        }

        Integer monthFirst = MONTHS.get(parts[0]);
        Integer monthMiddle = MONTHS.get(parts[1]);
        Integer year = expandYear(toInt(parts[2]));
        if (monthFirst != null) {
            found.add(tryYmd(year, monthFirst, toInt(parts[1])));
        }
        if (monthMiddle != null) {
            found.add(tryYmd(year, monthMiddle, toInt(parts[0])));
        }
    }

    private static void addSeparatedNumericDates(Set<Date> found, String raw) {
        List<String> parts = tokenize(raw);
        if (parts.size() != 3) {
            return;
        }
        if (!parts[0].isNumeric() || !parts[1].isNumeric() || !parts[2].isNumeric()) {
            return;
        }

        Integer first = Integer.valueOf(parts[0]);
        Integer second = Integer.valueOf(parts[1]);
        Integer third = Integer.valueOf(parts[2]);
        if (first >= 100) {
            found.add(tryYmd(first, second, third));
            return;
        }

        Integer year = expandYear(third);
        found.add(tryYmd(year, first, second));
        found.add(tryYmd(year, second, first));
    }

    private static void addCompactDigitDates(Set<Date> found, String digits) {
        if (digits.length() == 8) {
            Integer firstFour = Integer.valueOf(digits.substring(0, 4));
            if (firstFour >= 1800 && firstFour <= 2100) {
                found.add(
                    tryYmd(
                        firstFour,
                        Integer.valueOf(digits.substring(4, 6)),
                        Integer.valueOf(digits.substring(6, 8))
                    )
                );
                return;
            }
            Integer year = Integer.valueOf(digits.substring(4, 8));
            Integer first = Integer.valueOf(digits.substring(0, 2));
            Integer second = Integer.valueOf(digits.substring(2, 4));
            found.add(tryYmd(year, first, second));
            found.add(tryYmd(year, second, first));
            return;
        }
        if (digits.length() == 6) {
            Integer first = Integer.valueOf(digits.substring(0, 2));
            Integer second = Integer.valueOf(digits.substring(2, 4));
            Integer third = Integer.valueOf(digits.substring(4, 6));
            found.add(tryYmd(expandYear(third), first, second));
            found.add(tryYmd(expandYear(third), second, first));
            found.add(tryYmd(expandYear(first), second, third));
        }
    }

    private static DateRange parseMonthYear(String raw) {
        List<String> parts = tokenize(ORDINAL.matcher(raw.toLowerCase()).replaceAll('$1'));
        if (parts.size() != 2) {
            return null;
        }

        Integer month = MONTHS.get(parts[0]);
        Integer year = expandYear(toInt(parts[1]));
        if (month == null) {
            month = MONTHS.get(parts[1]);
            year = expandYear(toInt(parts[0]));
        }
        if (month == null && parts[0].isNumeric() && parts[1].isNumeric()) {
            Integer first = Integer.valueOf(parts[0]);
            Integer second = Integer.valueOf(parts[1]);
            if (first >= 1800 && first <= 2100 && second >= 1 && second <= 12) {
                year = first;
                month = second;
            } else if (second >= 1800 && second <= 2100 && first >= 1 && first <= 12) {
                year = second;
                month = first;
            }
        }
        if (month == null || year == null || year < 1800 || year > 2100) {
            return null;
        }
        Date startDate = Date.newInstance(year, month, 1);
        return new DateRange(startDate, startDate.addMonths(1).addDays(-1));
    }

    private static Boolean isAllNumericTokens(String raw) {
        List<String> parts = tokenize(raw);
        if (parts.isEmpty()) {
            return false;
        }
        for (String part : parts) {
            if (!part.isNumeric()) {
                return false;
            }
        }
        return true;
    }

    private static List<String> tokenize(String raw) {
        List<String> parts = new List<String>();
        if (String.isBlank(raw)) {
            return parts;
        }
        for (String part : raw.trim().toLowerCase().split('[\\s/\\-.,]+')) {
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        return parts;
    }

    private static Integer toInt(String value) {
        if (String.isBlank(value) || !value.isNumeric()) {
            return null;
        }
        return Integer.valueOf(value);
    }

    private static Integer expandYear(Integer year) {
        if (year == null) {
            return null;
        }
        if (year >= 100) {
            return year;
        }
        Integer thisYear = Date.today().year();
        Integer century = (thisYear / 100) * 100;
        Integer pivot = Math.mod(thisYear, 100) + 1;
        return year <= pivot ? century + year : century - 100 + year;
    }

    private static Date tryYmd(Integer year, Integer month, Integer day) {
        if (year == null || month == null || day == null) {
            return null;
        }
        if (year < 1800 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
            return null;
        }
        try {
            Date parsed = Date.newInstance(year, month, day);
            if (parsed.year() != year || parsed.month() != month || parsed.day() != day) {
                return null;
            }
            return parsed;
        } catch (Exception e) {
            return null;
        }
    }
}
