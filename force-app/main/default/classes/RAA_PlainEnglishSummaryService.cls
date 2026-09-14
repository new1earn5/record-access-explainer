/**
 * Renders a completed scan's already-computed, structured results as a short plain-English
 * paragraph - counts, access levels, and reason categories tallied from the exact same
 * RAA_AccessResultDTO/RAA_AccessReasonDTO data the results grid already shows, assembled into
 * fixed sentence templates. Deliberately not a generative-AI call: every sentence is built from a
 * real count that can be traced back to the grid, consistent with this package's "never guess"
 * philosophy, and it stays testable and callout-free the same way the rest of the app is.
 */
public without sharing class RAA_PlainEnglishSummaryService {
    public String buildSummary(RAA_AnalysisSummaryDTO summary, List<RAA_AccessResultDTO> results) {
        String recordDescription = describeRecord(summary);
        if (results == null || results.isEmpty()) {
            return 'No users currently have access to ' + recordDescription + '.';
        }

        List<String> sentences = new List<String>();
        sentences.add(openingSentence(recordDescription, results));

        String guestUsers = guestUserSentence(results);
        if (guestUsers != null) {
            sentences.add(guestUsers);
        }

        String accessLevels = accessLevelSentence(results);
        if (accessLevels != null) {
            sentences.add(accessLevels);
        }

        String reasons = reasonBreakdownSentence(results);
        if (reasons != null) {
            sentences.add(reasons);
        }

        String unresolved = unresolvedSentence(results);
        if (unresolved != null) {
            sentences.add(unresolved);
        }

        String lowConfidence = lowConfidenceSentence(results);
        if (lowConfidence != null) {
            sentences.add(lowConfidence);
        }

        if (summary != null && summary.potentiallyIncomplete == true) {
            sentences.add(
                'This scan is marked potentially incomplete - see the warning banner for details before relying on this summary.'
            );
        }

        return String.join(sentences, ' ');
    }

    private String describeRecord(RAA_AnalysisSummaryDTO summary) {
        String displayName = summary != null && String.isNotBlank(summary.recordDisplayName)
            ? summary.recordDisplayName
            : 'this record';
        return summary != null && String.isNotBlank(summary.objectApiName)
            ? displayName + ' (' + summary.objectApiName + ')'
            : displayName;
    }

    private String openingSentence(String recordDescription, List<RAA_AccessResultDTO> results) {
        return pluralCount(results.size(), 'user has', 'users have') + ' access to ' + recordDescription + '.';
    }

    private String accessLevelSentence(List<RAA_AccessResultDTO> results) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (RAA_AccessResultDTO result : results) {
            String level = String.isNotBlank(result.maxAccessLevel) ? result.maxAccessLevel : 'Unknown';
            increment(counts, level);
        }
        List<String> clauses = new List<String>();
        for (CountEntry entry : sortedDescending(counts)) {
            clauses.add(pluralCount(entry.count, 'user has', 'users have') + ' ' + entry.label + ' access');
        }
        return clauses.isEmpty() ? null : 'By access level, ' + joinWithAnd(clauses) + '.';
    }

    private String reasonBreakdownSentence(List<RAA_AccessResultDTO> results) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (RAA_AccessResultDTO result : results) {
            if (result.reasons != null && !result.reasons.isEmpty() && String.isNotBlank(result.reasons[0].category)) {
                increment(counts, result.reasons[0].category);
            }
        }
        List<String> clauses = new List<String>();
        for (CountEntry entry : sortedDescending(counts)) {
            clauses.add(entry.label + ' (' + pluralCount(entry.count, 'user', 'users') + ')');
        }
        return clauses.isEmpty() ? null : 'Access is primarily explained by ' + joinWithAnd(clauses) + '.';
    }

    // Reported ahead of and separately from the general access-level breakdown: Guest User
    // record access is the single most common real-world cause of public Salesforce data
    // exposure, and deserves to stand out rather than being folded into a generic access-level
    // count an admin might skim past.
    private String guestUserSentence(List<RAA_AccessResultDTO> results) {
        Integer guestCount = 0;
        for (RAA_AccessResultDTO result : results) {
            if (result.userType == 'Guest') {
                guestCount++;
            }
        }
        if (guestCount == 0) {
            return null;
        }
        return pluralCount(guestCount, 'Guest User has', 'Guest Users have') +
            ' access to this record - verify this is intentional, since Guest User access is what backs public Experience Cloud sites and Sites, and is a common source of unintended public data exposure.';
    }

    private String unresolvedSentence(List<RAA_AccessResultDTO> results) {
        Integer unresolvedCount = 0;
        for (RAA_AccessResultDTO result : results) {
            if (result.hasUnresolvedReason == true) {
                unresolvedCount++;
            }
        }
        if (unresolvedCount == 0) {
            return null;
        }
        return 'For ' +
            pluralCount(unresolvedCount, 'user', 'users') +
            ', access could not be fully attributed to a specific mechanism and may need manual review.';
    }

    private String lowConfidenceSentence(List<RAA_AccessResultDTO> results) {
        Integer lowConfidenceCount = 0;
        for (RAA_AccessResultDTO result : results) {
            if (result.overallConfidence == 'Low' || result.overallConfidence == 'Mixed') {
                lowConfidenceCount++;
            }
        }
        if (lowConfidenceCount == 0) {
            return null;
        }
        return 'For ' +
            pluralCount(lowConfidenceCount, 'user', 'users') +
            ', the reason was determined with only Low or Mixed confidence - review individually before relying on this summary.';
    }

    private String pluralCount(Integer count, String singularSuffix, String pluralSuffix) {
        return count + ' ' + (count == 1 ? singularSuffix : pluralSuffix);
    }

    private void increment(Map<String, Integer> counts, String key) {
        counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
    }

    private List<CountEntry> sortedDescending(Map<String, Integer> counts) {
        List<CountEntry> entries = new List<CountEntry>();
        for (String key : counts.keySet()) {
            entries.add(new CountEntry(key, counts.get(key)));
        }
        entries.sort(new ByCountDescending());
        return entries;
    }

    private String joinWithAnd(List<String> clauses) {
        if (clauses.size() == 1) {
            return clauses[0];
        }
        List<String> allButLast = new List<String>(clauses);
        String last = allButLast.remove(allButLast.size() - 1);
        return String.join(allButLast, ', ') + ', and ' + last;
    }

    private class CountEntry {
        String label;
        Integer count;
        CountEntry(String label, Integer count) {
            this.label = label;
            this.count = count;
        }
    }

    private class ByCountDescending implements Comparator<CountEntry> {
        public Integer compare(CountEntry a, CountEntry b) {
            if (b.count != a.count) {
                return b.count - a.count;
            }
            return a.label.compareTo(b.label);
        }
    }
}
