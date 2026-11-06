#include "prison/protocol.hpp"
#include <openssl/ssl.h>
#include <algorithm>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <memory>
#include <random>
#include <cstring>
using namespace prison;
namespace {
std::size_t checks=0;
void check(bool ok,const char* message){++checks;if(!ok)throw Error(message);}
template<class F>void rejects(F f,const char* message){bool rejected=false;try{f();}catch(const Error&){rejected=true;}check(rejected,message);}
Bytes file(const std::string& path){std::ifstream f(path,std::ios::binary);if(!f)throw Error("Missing Swift fixture");return Bytes(std::istreambuf_iterator<char>(f),{});}
unsigned int client_psk(SSL* ssl,const char*,char* identity,unsigned int identity_max,unsigned char* key,unsigned int key_max){
    constexpr char label[]="AireDisplay-v1";
    const auto* secret=static_cast<const Bytes*>(SSL_CTX_get_app_data(SSL_get_SSL_CTX(ssl)));
    if(identity_max<sizeof(label)||!secret||key_max<secret->size())return 0;
    std::memcpy(identity,label,sizeof(label));std::copy(secret->begin(),secret->end(),key);return static_cast<unsigned int>(secret->size());
}
unsigned int server_psk(SSL* ssl,const char* identity,unsigned char* key,unsigned int key_max){
    const auto* secret=static_cast<const Bytes*>(SSL_CTX_get_app_data(SSL_get_SSL_CTX(ssl)));
    if(!identity||std::strcmp(identity,"AireDisplay-v1")||!secret||key_max<secret->size())return 0;
    std::copy(secret->begin(),secret->end(),key);return static_cast<unsigned int>(secret->size());
}
bool handshake(bool correct){
    auto secret=psk_secret("0123456789ABCDEF0123456789ABCDEF"),remote=secret;
    if(!correct)remote[0]^=1;
    using Context=std::unique_ptr<SSL_CTX,decltype(&SSL_CTX_free)>;
    using Session=std::unique_ptr<SSL,decltype(&SSL_free)>;
    Context client(SSL_CTX_new(TLS_method()),SSL_CTX_free),server(SSL_CTX_new(TLS_method()),SSL_CTX_free);
    check(bool(client)&&bool(server),"TLS allocation");
    for(auto* ctx:{client.get(),server.get()}){
        check(SSL_CTX_set_min_proto_version(ctx,TLS1_2_VERSION)==1 && SSL_CTX_set_max_proto_version(ctx,TLS1_2_VERSION)==1,"TLS 1.2 profile");
        check(SSL_CTX_set_cipher_list(ctx,"PSK-AES128-GCM-SHA256")==1,"Mac PSK cipher available");
    }
    SSL_CTX_set_app_data(client.get(),&secret);SSL_CTX_set_app_data(server.get(),&remote);
    SSL_CTX_set_psk_client_callback(client.get(),client_psk);SSL_CTX_set_psk_server_callback(server.get(),server_psk);
    Session a(SSL_new(client.get()),SSL_free),b(SSL_new(server.get()),SSL_free);
    BIO *ab=nullptr,*ba=nullptr;check(BIO_new_bio_pair(&ab,0,&ba,0)==1,"TLS memory channel");
    SSL_set_bio(a.get(),ab,ab);SSL_set_bio(b.get(),ba,ba);SSL_set_connect_state(a.get());SSL_set_accept_state(b.get());
    for(int i=0;i<100;++i){
        for(auto* s:{a.get(),b.get()}){
            if(SSL_is_init_finished(s))continue;
            const int result=SSL_do_handshake(s);
            if(result!=1){const auto error=SSL_get_error(s,result);if(error!=SSL_ERROR_WANT_READ&&error!=SSL_ERROR_WANT_WRITE)return false;}
        }
        if(SSL_is_init_finished(a.get())&&SSL_is_init_finished(b.get())){
            const auto payload=frame({Kind::hello,encode(Hello{"sender","0.4.22","Windows de prueba"})});
            check(SSL_write(a.get(),payload.data(),static_cast<int>(payload.size()))==static_cast<int>(payload.size()),"TLS writes hello");
            Bytes received(payload.size());check(SSL_read(b.get(),received.data(),static_cast<int>(received.size()))==static_cast<int>(payload.size())&&received==payload,"TLS authenticates complete payload");
            check(SSL_version(a.get())==TLS1_2_VERSION,"TLS negotiated expected revision");return true;
        }
    }
    return false;
}
}
int main(int argc,char** argv){try{
    if(argc!=2)throw Error("Expected fixture directory");const std::string root=argv[1];
    const auto hello=file(root+"/hello.bin");const auto h=decode_hello(hello,"sender","0.4.28");
    check(h.name=="Mac de prueba ñ"&&encode(h)==hello,"Swift hello is byte-identical");
    rejects([&]{decode_hello(hello,"receiver","0.4.28");},"Role confusion rejected");
    rejects([&]{decode_hello(hello,"sender","0.4.23");},"Version mismatch rejected");
    rejects([&]{encode(Hello{"sender","0.4.22",std::string("bad\0name",8)});},"Control name rejected");
    rejects([&]{encode(Hello{"sender","0.4.22",std::string("\xc0\xaf",2)});},"Invalid UTF-8 rejected");
    const auto mouse=file(root+"/mouse.bin");const auto m=decode_pointer(mouse);
    check(m.x==0.25&&m.y==0.75&&m.clicks==2&&m.delta_x==7&&encode(m)==mouse,"Swift pointer preserves position, wheel, modifiers and double click");
    const auto keyboard=file(root+"/keyboard.bin");const auto k=decode_keyboard(keyboard);
    check(k.code==8&&k.repeated&&encode(k)==keyboard,"Swift key is byte-identical");
    const auto desktop=file(root+"/desktop.bin");const auto c=decode_desktop_control(desktop);
    check(c.width==1920&&c.height==1080&&c.token==123456789&&encode(c)==desktop,"Swift desktop lease is byte-identical");
    const auto video=file(root+"/video.bin");check(encode(decode_video(video))==video,"Real Mac H264 payload roundtrips exactly");
    check(psk_secret("0123456789abcdef0123456789abcdef")==file(root+"/psk.bin"),"PSK derivation matches CryptoKit SHA256");
    check(frame({Kind::hello,hello})==file(root+"/packet.bin"),"Packet framing matches Swift");
    auto framed=frame({Kind::hello,hello});Parser parser;std::vector<Packet> packets;
    for(auto byte:framed)parser.feed(Bytes{byte},[&](Packet p){packets.push_back(std::move(p));});
    check(packets.size()==1&&packets[0].body==hello&&parser.buffered()==0,"Byte-at-a-time transport segmentation");
    Bytes many;for(int i=0;i<100;++i)many.insert(many.end(),framed.begin(),framed.end());
    int received=0;parser.feed(many,[&](Packet){++received;});check(received==100&&parser.buffered()==0,"Coalesced packets parsed without a growing FIFO");
    Parser broken;rejects([&]{broken.feed(Bytes{0xff,0xff,0xff,0xff},[](Packet){});},"Oversized frame rejected before body allocation");
    check(broken.buffered()==0,"Failed parser drops buffered data");rejects([&]{broken.feed(framed,[](Packet){});},"Failed parser cannot resume");
    rejects([&]{auto bad=m;bad.x=std::numeric_limits<double>::quiet_NaN();encode(bad);},"NaN coordinate rejected");
    rejects([&]{auto bad=m;bad.x=1.01;encode(bad);},"Out-of-display coordinate rejected");
    rejects([&]{auto bad=k;bad.flags=1;encode(bad);},"Unrecognized key modifiers rejected");
    rejects([&]{encode(DesktopControl{});},"Empty desktop token rejected");
    rejects([&]{auto bad=decode_video(video);bad.avcc={0,0,0,5,0};encode(bad);},"Truncated NAL rejected");
    LatestCursor cursor;for(int i=0;i<1000;++i){Pointer move;move.x=double(i)/1000;cursor.offer(move);}
    check(cursor.take()->x==0.999&&!cursor.take(),"Cursor backlog retains latest position only");
    rejects([&]{cursor.offer(m);},"Clicks never enter cursor mailbox");
    InputPolicy policy;policy.configure(true,true);
    check(bool(policy.accept({Kind::pointer,mouse}))&&bool(policy.accept({Kind::keyboard,keyboard})),"Independent channels accept enabled input");
    const auto mouse_off=policy.configure(false,true);
    check(mouse_off.size()==1&&mouse_off[0].kind==Kind::pointer&&decode_pointer(mouse_off[0].body).action==Pointer::Action::left_up,"Mouse-off releases its held button only");
    check(!policy.accept({Kind::pointer,mouse})&&bool(policy.accept({Kind::keyboard,keyboard})),"Keyboard remains active with mouse disabled");
    const auto keys_off=policy.configure(true,false);check(keys_off.size()==1&&keys_off[0].kind==Kind::keyboard,"Keyboard-off releases its keys only");
    const auto clean=policy.accept({Kind::pointer,mouse});check(clean&&decode_pointer(clean->body).flags==0&&!policy.accept({Kind::keyboard,keyboard}),"Mouse remains usable without leaking disabled keyboard modifiers");
    check(!policy.disconnect().empty(),"Disconnect releases held input");
    std::mt19937 random(1701);
    for(int trial=0;trial<10000;++trial){
        Bytes data(static_cast<std::size_t>(random()%100));for(auto& byte:data)byte=static_cast<std::uint8_t>(random());
        try{const auto p=decode_pointer(data);check(encode(p)==data,"Fuzz pointer roundtrip");}catch(const Error&){}
        try{const auto p=decode_keyboard(data);check(encode(p)==data,"Fuzz key roundtrip");}catch(const Error&){}
        Parser fuzz;try{fuzz.feed(data,[](Packet){});}catch(const Error&){}check(fuzz.buffered()<=max_packet+4,"Parser bound under malformed input");
    }
    check(handshake(true),"TLS-PSK encrypts/authenticates the Mac profile");
    check(!handshake(false),"TLS rejects an incorrect pairing secret");
    std::cout<<"PASS "<<checks<<" checks; Swift fixture interoperability, input independence, malformed packets and TLS-PSK. No screen or OS input accessed.\n";
    return 0;
}catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}}
