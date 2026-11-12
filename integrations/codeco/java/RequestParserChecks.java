import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

public final class RequestParserChecks {
    private static void check(boolean result,String label){if(!result)throw new IllegalStateException(label);}
    private static void rejected(String xml) throws Exception {
        try{RequestParser.request(xml);throw new IllegalStateException("unsafe XML accepted");}
        catch(IllegalArgumentException|org.xml.sax.SAXException expected){}
    }
    public static void main(String[] args) throws Exception {
        String xml=Files.readString(Path.of(args[0]),StandardCharsets.UTF_8);
        Map<String,String> parsed=RequestParser.request(xml);
        check("MSCMAR".equals(parsed.get("clientId")),"request client");
        check("2026-07-12T00:08Z".equals(parsed.get("requestGenerationDate")),"lexical timestamp retained");
        check(RequestParser.json(parsed).contains("\"voyageNumber\":\"\""),"empty fields retained");
        rejected("<!DOCTYPE OutgoingMessageRequest [<!ENTITY x SYSTEM 'file:///never-read'>]>"+xml.replaceFirst("<\\?xml[^>]*>",""));
        rejected(xml.replace("</OutgoingMessageRequest>","<clientId>OTHER</clientId></OutgoingMessageRequest>"));
        rejected(xml.replace("<clientId>MSCMAR</clientId>","<clientId><nested>MSCMAR</nested></clientId>"));
        rejected(xml.replace("<OutgoingMessageRequest>","<OutgoingMessageRequest xmlns='urn:unexpected'>"));
        if(args.length>1){
            String response=Files.readString(Path.of(args[1]),StandardCharsets.UTF_8);
            RequestParser.validateResponse(response,parsed);
            Map<String,String> wrong=new java.util.LinkedHashMap<>(parsed);wrong.put("terminalId","WRONG");
            try{RequestParser.validateResponse(response,wrong);throw new IllegalStateException("wrong reply accepted");}
            catch(IllegalArgumentException expected){}
        }
        System.out.println("PASS: sample request, lexical echo fields, DTD/XXE, duplicate fields, nesting and namespace rejection.");
    }
}
