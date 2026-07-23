/**
 * Builds CSV text for the results grid and for the full reason detail, from already-authorized
 * DTOs (no SOQL or DML here - purely string formatting). Values are escaped per RFC 4180: any
 * field containing a comma, double quote, or line break is wrapped in double quotes, with
 * embedded double quotes doubled.
 */
public with sharing class RAA_CsvExportService {
    private static final List<String> RESULT_HEADERS = new List<String>{
        'User',
        'Username',
        'Active',
        'User Type',
        'Profile',
        'Max Access',
        'Read',
        'Edit',
        'Delete',
        'Transfer',
        'All Access',
        'Reason Summary',
        'Confidence'
    };

    private static final List<String> REASON_HEADERS = new List<String>{
        'User',
        'Username',
        'Category',
        'Access Level',
        'Confidence',
        'Direct',
        'Source',
        'Row Cause',
        'Grant Path',
        'Explanation'
    };

    public String buildResultsCsv(List<RAA_AccessResultDTO> results) {
        List<String> lines = new List<String>{ String.join(RESULT_HEADERS, ',') };
        if (results != null) {
            for (RAA_AccessResultDTO result : results) {
                List<String> row = new List<String>{
                    escape(result.userFullName),
                    escape(result.username),
                    String.valueOf(result.isActive),
                    escape(result.userType),
                    escape(result.profileName),
                    escape(result.maxAccessLevel),
                    String.valueOf(result.hasReadAccess),
                    String.valueOf(result.hasEditAccess),
                    String.valueOf(result.hasDeleteAccess),
                    String.valueOf(result.hasTransferAccess),
                    String.valueOf(result.hasAllAccess),
                    escape(result.reasonSummary),
                    escape(result.overallConfidence)
                };
                lines.add(String.join(row, ','));
            }
        }
        return String.join(lines, '\n');
    }

    public String buildReasonsCsv(List<RAA_AccessResultDTO> results) {
        List<String> lines = new List<String>{ String.join(REASON_HEADERS, ',') };
        if (results != null) {
            for (RAA_AccessResultDTO result : results) {
                if (result.reasons == null) {
                    continue;
                }
                for (RAA_AccessReasonDTO reason : result.reasons) {
                    List<String> row = new List<String>{
                        escape(result.userFullName),
                        escape(result.username),
                        escape(reason.category),
                        escape(reason.accessLevel),
                        escape(reason.confidence),
                        String.valueOf(reason.isDirect),
                        escape(reason.sourceName),
                        escape(reason.rowCause),
                        escape(reason.grantPath),
                        escape(reason.explanation)
                    };
                    lines.add(String.join(row, ','));
                }
            }
        }
        return String.join(lines, '\n');
    }

    private String escape(String value) {
        if (value == null) {
            return '';
        }
        Boolean needsQuoting =
            value.contains(',') ||
            value.contains('"') ||
            value.contains('\n') ||
            value.contains('\r');
        String escaped = value.replace('"', '""');
        return needsQuoting ? '"' + escaped + '"' : escaped;
    }
}
