import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Hashtable;
import java.util.Map;
import javax.jms.Connection;
import javax.jms.ConnectionFactory;
import javax.jms.DeliveryMode;
import javax.jms.Message;
import javax.jms.MessageConsumer;
import javax.jms.MessageProducer;
import javax.jms.Session;
import javax.jms.TextMessage;
import javax.jms.Topic;
import javax.naming.Context;
import javax.naming.InitialContext;

/** JMS 1.1 bridge. Vendor JARs must be provided by webMethods IT, never downloaded from an unofficial source. */
public final class CodecoGateway {
    private static String required(String key){String value=System.getenv(key);if(value==null||value.isBlank())throw new IllegalArgumentException("missing_configuration");return value;}
    private static String optional(String key,String fallback){String value=System.getenv(key);return value==null||value.isBlank()?fallback:value;}
    private static final String REQUEST_TOPIC="logistic/outgoingMessagesRequest/xmlOutgoingMessagesRequestTopic";
    private static final String RESPONSE_TOPIC="logistic/containerDepartureConfirmationMessage/xmlContainerDepartureConfirmationMessageTopic";
    public static void main(String[] args) {
        Connection connection=null; Session session=null; InitialContext naming=null; int exitCode=0;
        try{
            URI endpoint=URI.create(required("CODECO_API_URL"));
            boolean loopback="http".equals(endpoint.getScheme())&&SetHelper.local(endpoint.getHost());
            if((!loopback&&!"https".equals(endpoint.getScheme()))||endpoint.getUserInfo()!=null||endpoint.getRawQuery()!=null||endpoint.getRawFragment()!=null)
                throw new IllegalArgumentException("invalid_api_url");
            String token=required("CODECO_API_TOKEN");if(token.length()<32)throw new IllegalArgumentException("invalid_api_token");
            Hashtable<String,String> env=new Hashtable<>();
            env.put(Context.INITIAL_CONTEXT_FACTORY,"com.pcbsys.nirvana.nSpace.NirvanaContextFactory");
            env.put(Context.PROVIDER_URL,required("JMS_PROVIDER_URL"));
            String user=System.getenv("JMS_USERNAME"),password=System.getenv("JMS_PASSWORD");
            if((user==null)!=(password==null))throw new IllegalArgumentException("incomplete_jms_credentials");
            if(user!=null){env.put(Context.SECURITY_PRINCIPAL,user);env.put(Context.SECURITY_CREDENTIALS,password);}
            naming=new InitialContext(env);
            ConnectionFactory factory=(ConnectionFactory)naming.lookup(required("JMS_CONNECTION_FACTORY"));
            connection=user==null?factory.createConnection():factory.createConnection(user,password);
            connection.setClientID(required("JMS_CLIENT_ID"));
            session=connection.createSession(true,Session.SESSION_TRANSACTED);
            Topic input=(Topic)naming.lookup(optional("JMS_REQUEST_TOPIC_JNDI",REQUEST_TOPIC)),output=(Topic)naming.lookup(optional("JMS_RESPONSE_TOPIC_JNDI",RESPONSE_TOPIC));
            MessageConsumer consumer=session.createDurableSubscriber(input,required("JMS_SUBSCRIPTION_NAME"));
            MessageProducer producer=session.createProducer(output); producer.setDeliveryMode(DeliveryMode.PERSISTENT);
            HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).followRedirects(HttpClient.Redirect.NEVER).build();
            connection.start();
            System.out.println("CODECO gateway ready; durable subscription active.");
            while(!Thread.currentThread().isInterrupted()){
                Message incoming=consumer.receive(1000);if(incoming==null)continue;
                try{
                    if(!(incoming instanceof TextMessage))throw new IllegalArgumentException("request_is_not_text");
                    Map<String,String> criteria=RequestParser.request(((TextMessage)incoming).getText());
                    String body=RequestParser.json(criteria);
                    HttpRequest request=HttpRequest.newBuilder(endpoint).timeout(Duration.ofSeconds(90))
                        .header("Authorization","Bearer "+token).header("Content-Type","application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(body,StandardCharsets.UTF_8)).build();
                    HttpResponse<InputStream> reply=http.send(request,HttpResponse.BodyHandlers.ofInputStream());
                    String xml;
                    try(InputStream stream=reply.body()){
                        byte[] bytes=stream.readNBytes(16000001);if(bytes.length>16000000)throw new IllegalArgumentException("response_limit");
                        xml=new String(bytes,StandardCharsets.UTF_8);
                    }
                    if(reply.statusCode()==204){session.commit();continue;}
                    if(reply.statusCode()!=200)throw new IllegalStateException("api_rejected_request");
                    RequestParser.validateResponse(xml,criteria);
                    TextMessage response=session.createTextMessage(xml);
                    String correlation=incoming.getJMSCorrelationID();
                    response.setJMSCorrelationID(correlation==null?incoming.getJMSMessageID():correlation);
                    producer.send(response);
                    session.commit(); // Receive acknowledgement and reply publication share ONE broker transaction.
                    System.out.println("CODECO response committed to broker; downstream MSC delivery is tracked by webMethods.");
                }catch(Exception failed){
                    try{session.rollback();}catch(Exception ignored){}
                    // Stop instead of acknowledging/loss or an endless poison-message loop. IT recovery/DLQ policy owns retries.
                    throw new IllegalStateException("request_failed_unacknowledged");
                }
            }
        }catch(Exception failed){
            // Never log credentials, connection strings, XML payloads or uncontrolled vendor exception messages.
            System.err.println("CODECO gateway stopped. Review the local API status and IT configuration; any failed request remains unacknowledged.");
            exitCode=1;
        }finally{
            if(session!=null)try{session.close();}catch(Exception ignored){}
            if(connection!=null)try{connection.close();}catch(Exception ignored){}
            if(naming!=null)try{naming.close();}catch(Exception ignored){}
        }
        if(exitCode!=0)System.exit(exitCode);
    }
    private static final class SetHelper {
        static boolean local(String host){return "127.0.0.1".equals(host)||"localhost".equalsIgnoreCase(host)||"[::1]".equals(host)||"::1".equals(host);}
    }
}
