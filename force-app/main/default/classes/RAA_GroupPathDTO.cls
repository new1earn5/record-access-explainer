/**
 * Internal (non Aura-enabled) representation of one resolved path through the
 * public-group / queue / role / territory membership graph from a principal down to a user.
 */
public class RAA_GroupPathDTO {
    public Id principalId;
    public String principalType;
    public String principalName;
    public List<String> pathSegments;

    public RAA_GroupPathDTO(Id principalId, String principalType, String principalName, List<String> pathSegments) {
        this.principalId = principalId;
        this.principalType = principalType;
        this.principalName = principalName;
        this.pathSegments = pathSegments;
    }

    public String renderPath(String finalSegment) {
        List<String> rendered = new List<String>(pathSegments);
        if (String.isNotBlank(finalSegment)) {
            rendered.add(finalSegment);
        }
        return String.join(rendered, ' -> ');
    }
}
