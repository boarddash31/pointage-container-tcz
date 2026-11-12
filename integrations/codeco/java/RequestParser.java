import java.io.StringReader;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;
import org.xml.sax.SAXParseException;
import org.xml.sax.helpers.DefaultHandler;

/** Vendor-independent XML boundary; compile with the IT-approved JDK (Java 11+). */
public final class RequestParser {
    private static final String[] FIELDS={"requestType","clientId","messageType","dateRangeFrom","rangeFrom",
        "dateRangeTo","rangeTo","voyageNumber","terminalId","requestGenerationDate","documentType","schema"};
    private static Document parse(String xml,int limit) throws Exception {
        if(xml==null||xml.length()>limit)throw new IllegalArgumentException("xml_size");
        if(xml.startsWith("\uFEFF"))xml=xml.substring(1);
        DocumentBuilderFactory f=DocumentBuilderFactory.newInstance();
        f.setNamespaceAware(true);
        f.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING,true);
        f.setFeature("http://apache.org/xml/features/disallow-doctype-decl",true);
        f.setFeature("http://xml.org/sax/features/external-general-entities",false);
        f.setFeature("http://xml.org/sax/features/external-parameter-entities",false);
        f.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd",false);
        f.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD,"");
        f.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA,"");
        f.setXIncludeAware(false); f.setExpandEntityReferences(false);
        DocumentBuilder b=f.newDocumentBuilder();
        b.setEntityResolver((publicId,systemId)->{throw new SAXException("external_entity_denied");});
        b.setErrorHandler(new DefaultHandler(){
            @Override public void error(SAXParseException e) throws SAXException {throw e;}
            @Override public void fatalError(SAXParseException e) throws SAXException {throw e;}
        });
        return b.parse(new InputSource(new StringReader(xml)));
    }
    public static Map<String,String> request(String xml) throws Exception {
        Document doc=parse(xml,8192); Element root=doc.getDocumentElement();
        if(!root.getTagName().equals("OutgoingMessageRequest")||root.getNamespaceURI()!=null||root.hasAttributes())
            throw new IllegalArgumentException("request_root");
        Map<String,String> values=new LinkedHashMap<>(); Set<String> allowed=Set.of(FIELDS);
        for(Node child=root.getFirstChild();child!=null;child=child.getNextSibling()){
            if(child instanceof Element){
                Element element=(Element)child; String name=element.getTagName();
                if(!allowed.contains(name)||values.containsKey(name)||element.hasAttributes()||element.getNamespaceURI()!=null)
                    throw new IllegalArgumentException("request_fields");
                for(Node n=element.getFirstChild();n!=null;n=n.getNextSibling())
                    if(n.getNodeType()!=Node.TEXT_NODE&&n.getNodeType()!=Node.CDATA_SECTION_NODE&&n.getNodeType()!=Node.COMMENT_NODE)
                        throw new IllegalArgumentException("request_nesting");
                String value=element.getTextContent();
                if(value.length()>512)throw new IllegalArgumentException("request_field_size");
                values.put(name,value);
            }else if(child.getNodeType()!=Node.COMMENT_NODE&& !child.getTextContent().trim().isEmpty())
                throw new IllegalArgumentException("request_text");
        }
        if(values.size()!=FIELDS.length)throw new IllegalArgumentException("missing_request_field");
        return values;
    }
    private static Element one(Element parent,String name){
        Element found=null;
        for(Node n=parent.getFirstChild();n!=null;n=n.getNextSibling())if(n instanceof Element&&n.getNodeName().equals(name)){
            if(found!=null)throw new IllegalArgumentException("duplicate_response_field");found=(Element)n;
        }
        if(found==null)throw new IllegalArgumentException("missing_response_field");
        return found;
    }
    public static void validateResponse(String xml,Map<String,String> criteria) throws Exception {
        Element root=parse(xml,16000000).getDocumentElement();
        if(!root.getTagName().equals("ContainerDepartureConfirmations")||root.getNamespaceURI()!=null||root.hasAttributes())
            throw new IllegalArgumentException("response_root");
        String[] echoed={"clientId","messageType","dateRangeFrom","rangeFrom","dateRangeTo","rangeTo","voyageNumber","terminalId","requestGenerationDate"};
        for(Node n=root.getFirstChild();n!=null;n=n.getNextSibling())if(n instanceof Element){
            Element confirmation=(Element)n;
            if(!confirmation.getTagName().equals("ContainerDepartureConfirmation"))throw new IllegalArgumentException("response_element");
            Element generation=one(one(confirmation,"Properties"),"MessageGeneration");
            for(String key:echoed)if(!criteria.get(key).equals(one(generation,key).getTextContent()))throw new IllegalArgumentException("response_request_mismatch");
            if(!one(generation,"schema").getTextContent().equals("marsa.canonicals.departureConfirmation.validation:ContainerDepartureConfirmationSchema")||
                !one(generation,"documentType").getTextContent().equals("marsa.canonicals.containerDepartureConfirmation:ContainerDepartureConfirmation"))
                throw new IllegalArgumentException("response_schema_mismatch");
        }
    }
    private static String quoted(String value){
        StringBuilder out=new StringBuilder("\"");
        for(int i=0;i<value.length();i++){
            char c=value.charAt(i);
            if(c=='"'||c=='\\')out.append('\\').append(c);
            else if(c<32)out.append(String.format("\\u%04x",(int)c));
            else out.append(c);
        }
        return out.append('"').toString();
    }
    public static String json(Map<String,String> values){
        StringBuilder out=new StringBuilder("{"); boolean first=true;
        for(String key:FIELDS){if(!first)out.append(',');first=false;out.append(quoted(key)).append(':').append(quoted(values.get(key)));}
        return out.append('}').toString();
    }
}
