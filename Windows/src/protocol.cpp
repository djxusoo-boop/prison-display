#include "prison/protocol.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <utility>
namespace prison { namespace {
struct Writer {
    Bytes bytes;
    void number(std::uint64_t value, unsigned count) {
        for (unsigned i=count; i>0; --i) bytes.push_back(static_cast<std::uint8_t>(value >> ((i-1)*8)));
    }
    void real(double value) { std::uint64_t bits; static_assert(sizeof(bits)==sizeof(value)); std::memcpy(&bits,&value,8); number(bits,8); }
    void append(const Bytes& value) { bytes.insert(bytes.end(),value.begin(),value.end()); }
};
struct Reader {
    const Bytes& data; std::size_t offset=0;
    std::size_t remaining() const { return data.size()-offset; }
    std::uint64_t number(unsigned count) {
        if (count > remaining()) throw Error("Truncated message");
        std::uint64_t value=0; while (count--) value=(value<<8)|data[offset++]; return value;
    }
    Bytes bytes(std::size_t count) {
        if (count > remaining()) throw Error("Truncated message");
        Bytes value(data.begin()+static_cast<std::ptrdiff_t>(offset),data.begin()+static_cast<std::ptrdiff_t>(offset+count));
        offset+=count; return value;
    }
    double real() { const auto bits=number(8); double value; std::memcpy(&value,&bits,8); return value; }
    void end() { if (remaining()) throw Error("Trailing bytes"); }
};
void name_valid(const std::string& name) {
    if (name.empty() || name.size()>256) throw Error("Invalid computer name");
    std::size_t index=0, count=0;
    while (index<name.size()) {
        const auto first=static_cast<unsigned char>(name[index++]); std::uint32_t cp=first;
        unsigned extra=0; std::uint32_t minimum=0;
        if (first>=0xc2 && first<=0xdf) { extra=1; cp=first&0x1f; minimum=0x80; }
        else if (first>=0xe0 && first<=0xef) { extra=2; cp=first&0x0f; minimum=0x800; }
        else if (first>=0xf0 && first<=0xf4) { extra=3; cp=first&0x07; minimum=0x10000; }
        else if (first>=0x80) throw Error("Invalid UTF-8 name");
        if (extra>name.size()-index) throw Error("Invalid UTF-8 name");
        for (unsigned n=0;n<extra;++n) {
            const auto next=static_cast<unsigned char>(name[index++]);
            if ((next&0xc0)!=0x80) throw Error("Invalid UTF-8 name");
            cp=(cp<<6)|(next&0x3f);
        }
        if ((extra && cp<minimum) || cp>0x10ffff || (cp>=0xd800 && cp<=0xdfff) || cp<32 || (cp>=0x7f && cp<=0x9f)) throw Error("Invalid computer name");
        if (++count>64) throw Error("Computer name too long");
    }
    if (name.front()==' ' || name.back()==' ') throw Error("Unnormalized computer name");
}
void pointer_valid(const Pointer& p) {
    if (static_cast<unsigned>(p.action)>8 || !std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.delta) || !std::isfinite(p.delta_x)
        || p.x<0 || p.x>1 || p.y<0 || p.y>1 || std::abs(p.delta)>120 || std::abs(p.delta_x)>120 || p.clicks<1 || p.clicks>3 || (p.flags&~allowed_input_flags)) throw Error("Invalid pointer");
}
void keyboard_valid(const Keyboard& k) {
    if (static_cast<unsigned>(k.action)>3 || k.code>127 || (k.flags&~allowed_input_flags)
        || (k.action==Keyboard::Action::release_all && (k.code || k.flags || k.repeated))) throw Error("Invalid keyboard");
}
void control_valid(const DesktopControl& c) {
    if (static_cast<unsigned>(c.action)>6 || !c.token) throw Error("Invalid desktop control");
    if (c.action==DesktopControl::Action::accepted) {
        if (c.width<4 || c.width>32768 || c.height<4 || c.height>32768) throw Error("Invalid desktop size");
    } else if (c.action==DesktopControl::Action::returned) {
        if (c.width>65535 || c.height>65535) throw Error("Invalid return position");
    } else if (c.width || c.height) throw Error("Unexpected desktop dimensions");
}
void video_valid(const VideoFrame& v) {
    if (v.sps.empty() || v.pps.empty() || v.sps.size()>4096 || v.pps.size()>4096 || v.avcc.empty()
        || v.avcc.size()+v.sps.size()+v.pps.size()+20>=max_packet) throw Error("Invalid H264 header");
    Reader reader{v.avcc};
    while (reader.remaining()) {
        auto length=reader.number(4);
        if (!length || length>reader.remaining()) throw Error("Invalid H264 NAL");
        reader.offset+=static_cast<std::size_t>(length);
    }
}
} // namespace
Bytes frame(const Packet& p) {
    const auto kind=static_cast<unsigned>(p.kind);
    if (kind<1 || kind>18 || p.body.size()>=max_packet) throw Error("Invalid packet");
    Writer w; w.number(p.body.size()+1,4); w.number(kind,1); w.append(p.body); return w.bytes;
}
void Parser::feed(const Bytes& data,const std::function<void(Packet)>& receive) {
    if (failed_) throw Error("Parser already failed");
    try {
        std::size_t position=0;
        while (position<data.size()) {
            std::size_t target=4;
            if (buffer_.size()>=4) {
                Reader r{buffer_}; const auto length=r.number(4);
                if (!length || length>max_packet) throw Error("Invalid packet length");
                target=static_cast<std::size_t>(length)+4;
            }
            const auto count=std::min(target-buffer_.size(),data.size()-position);
            buffer_.insert(buffer_.end(),data.begin()+static_cast<std::ptrdiff_t>(position),data.begin()+static_cast<std::ptrdiff_t>(position+count)); position+=count;
            if (buffer_.size()<4) continue;
            Reader r{buffer_}; const auto length=r.number(4);
            if (!length || length>max_packet) throw Error("Invalid packet length");
            if (buffer_.size()!=length+4) continue;
            const auto kind=r.number(1);
            if (kind<1 || kind>19) throw Error("Unknown packet kind");
            Packet packet{static_cast<Kind>(kind),r.bytes(r.remaining())}; buffer_.clear(); receive(std::move(packet));
        }
    } catch (...) { buffer_.clear(); failed_=true; throw; }
}
Bytes encode(const Hello& h) {
    name_valid(h.name);
    if (h.role.empty() || h.version.empty() || h.role.find('|')!=std::string::npos || h.version.find('|')!=std::string::npos) throw Error("Invalid hello");
    const auto text=h.role+"|"+h.version+"|"+base64(Bytes(h.name.begin(),h.name.end()));
    Writer w; w.number(wire_revision,2); w.bytes.insert(w.bytes.end(),text.begin(),text.end());
    if (w.bytes.size()>512) throw Error("Hello too long"); return w.bytes;
}
Hello decode_hello(const Bytes& bytes,const std::string& role,const std::string& version) {
    if (bytes.size()>512) throw Error("Hello too long");
    Reader r{bytes}; if (r.number(2)!=wire_revision) throw Error("Protocol revision mismatch");
    const auto body=r.bytes(r.remaining()); std::string text(body.begin(),body.end());
    const auto a=text.find('|'), b=a==std::string::npos ? a : text.find('|',a+1);
    if (a==std::string::npos || b==std::string::npos || text.find('|',b+1)!=std::string::npos) throw Error("Invalid hello fields");
    Hello h{text.substr(0,a),text.substr(a+1,b-a-1),{}};
    if (h.role!=role || (!version.empty() && h.version!=version)) throw Error("Peer role or version mismatch");
    const auto name=unbase64(text.substr(b+1)); h.name.assign(name.begin(),name.end()); name_valid(h.name); return h;
}
Bytes encode(const Pointer& p) {
    pointer_valid(p); Writer w; w.number(static_cast<unsigned>(p.action),1); w.real(p.x); w.real(p.y); w.real(p.delta); w.number(p.clicks,1); w.real(p.delta_x); w.number(p.flags,8); return w.bytes;
}
Pointer decode_pointer(const Bytes& bytes) {
    if (bytes.size()!=42) throw Error("Invalid pointer length"); Reader r{bytes}; Pointer p;
    p.action=static_cast<Pointer::Action>(r.number(1)); p.x=r.real();p.y=r.real();p.delta=r.real();p.clicks=static_cast<std::uint8_t>(r.number(1));p.delta_x=r.real();p.flags=r.number(8);pointer_valid(p);return p;
}
Bytes encode(const Keyboard& k) { keyboard_valid(k); Writer w;w.number(static_cast<unsigned>(k.action),1);w.number(k.code,2);w.number(k.flags,8);w.number(k.repeated?1:0,1);return w.bytes; }
Keyboard decode_keyboard(const Bytes& bytes) {
    if(bytes.size()!=12) throw Error("Invalid keyboard length"); Reader r{bytes};Keyboard k;
    k.action=static_cast<Keyboard::Action>(r.number(1));k.code=static_cast<std::uint16_t>(r.number(2));k.flags=r.number(8);
    const auto repeat=r.number(1);if(repeat>1)throw Error("Invalid repeat flag");k.repeated=repeat==1;keyboard_valid(k);return k;
}
Bytes encode(const DesktopControl& c) {control_valid(c);Writer w;w.number(static_cast<unsigned>(c.action),1);w.number(c.token,8);w.number(c.width,4);w.number(c.height,4);return w.bytes;}
DesktopControl decode_desktop_control(const Bytes& bytes) {
    if(bytes.size()!=17)throw Error("Invalid desktop control length");Reader r{bytes};DesktopControl c;
    c.action=static_cast<DesktopControl::Action>(r.number(1));c.token=r.number(8);c.width=static_cast<std::uint32_t>(r.number(4));c.height=static_cast<std::uint32_t>(r.number(4));control_valid(c);return c;
}
Bytes encode(const VideoFrame& v) {video_valid(v);Writer w;w.number(v.sequence,8);w.number(v.timestamp,8);w.number(v.sps.size(),2);w.append(v.sps);w.number(v.pps.size(),2);w.append(v.pps);w.append(v.avcc);return w.bytes;}
VideoFrame decode_video(const Bytes& bytes) {
    if(bytes.size()>=max_packet)throw Error("Video too large");Reader r{bytes};VideoFrame v;
    v.sequence=r.number(8);v.timestamp=r.number(8);v.sps=r.bytes(static_cast<std::size_t>(r.number(2)));v.pps=r.bytes(static_cast<std::size_t>(r.number(2)));v.avcc=r.bytes(r.remaining());video_valid(v);return v;
}
void LatestCursor::offer(Pointer p) {pointer_valid(p);if(p.action!=Pointer::Action::move)throw Error("Only cursor movement may be replaced");value_=p;}
std::optional<Pointer> LatestCursor::take(){auto result=value_;value_.reset();return result;}
std::vector<Packet> InputPolicy::configure(bool mouse,bool keyboard) {
    std::vector<Packet> releases;
    if(!mouse) {
        if(left_) {auto p=position_;p.action=Pointer::Action::left_up;releases.push_back({Kind::pointer,encode(p)});}
        if(right_) {auto p=position_;p.action=Pointer::Action::right_up;releases.push_back({Kind::pointer,encode(p)});}
        left_=right_=false;
    }
    if(!keyboard && keys_) {releases.push_back({Kind::keyboard,encode(Keyboard{})});keys_=false;}
    mouse_=mouse;keyboard_=keyboard;return releases;
}
std::optional<Packet> InputPolicy::accept(const Packet& packet) {
    if(packet.kind==Kind::pointer) {
        auto p=decode_pointer(packet.body);if(!mouse_)return {};
        if(!keyboard_)p.flags=0;
        position_=p;
        if(p.action==Pointer::Action::left_down)left_=true;
        if(p.action==Pointer::Action::left_up)left_=false;
        if(p.action==Pointer::Action::right_down)right_=true;
        if(p.action==Pointer::Action::right_up)right_=false;
        return Packet{packet.kind,encode(p)};
    }
    if(packet.kind==Kind::keyboard) {
        const auto k=decode_keyboard(packet.body);if(!keyboard_)return {};
        // Conservative: release-all on switch/disconnect, even if an ordinary
        // key-up has arrived while a different key remains held.
        if(k.action==Keyboard::Action::down || k.action==Keyboard::Action::modifiers)keys_=true;
        if(k.action==Keyboard::Action::release_all)keys_=false;
        return packet;
    }
    throw Error("Not an input packet");
}
std::vector<Packet> InputPolicy::disconnect(){auto releases=configure(false,false);mouse_=true;keyboard_=false;return releases;}
} // namespace prison
