/****************************************
           Torp Demo
****************************************/

/* Threshold I is populated by the switch operating system */
#define I 1000000

header_type ethernet_t {
    fields {
        dstAddr : 48;
        srcAddr : 48;
        etherType : 16;
    }
}

header_type ipv4_t {
    fields {
        version : 4;
        ihl : 4;
        diffserv : 8;
        totalLen : 16;
        identification : 16;
        flags : 3;
        fragOffset : 13;
        ttl : 8;
        protocol : 8;
        hdrChecksum : 16;
        srcAddr : 32;
        dstAddr: 32;
    }
}

header_type tcp_t {
    fields {
        src_port : 16;
        dst_port : 16;
        seq_no : 32;
        ack_no : 32;
        data_offset : 4;
        res : 3;
        ecn : 3;
        ctrl : 6;
        window : 16;
        checksum : 16;
        urgent_ptr : 16;
    }
}

header_type options_t {
    fields {
        option : 64;
    }
}

header_type intrinsic_metadata_t {
    fields {
        ingress_global_timestamp : 48;
        egress_global_timestamp : 48;
        mcast_grp : 16;
        egress_rid : 16;
        ingress_port : 9;
        egress_spec : 9;
    }
}
metadata intrinsic_metadata_t intrinsic_metadata;

header_type metadata_t {
    fields {
        t_minus: 48;
    }
}
metadata metadata_t md;

parser start {
    return parse_ethernet;
}

header ethernet_t ethernet;
parser parse_ethernet {
    extract(ethernet);
    return select(latest.etherType) {
        0x800 : parse_ipv4;
        default: ingress;
    }
}

header ipv4_t ipv4;
parser parse_ipv4 {
    extract(ipv4);
    return select(latest.totalLen) {
         0101 : parse_transport_layer;
        default : parse_option;
    }
}

header options_t options;
parser parse_option {
    extract(options);
    return parse_transport_layer;
}

parser parse_transport_layer {
    return select(ipv4.protocol) {
        6 : parse_tcp;
        default: ingress;
    }
}

header tcp_t tcp;
parser parse_tcp {
    extract(tcp);
    return ingress;
}

action add_options() {
    add_header(options);
    modify_field(options.option, intrinsic_metadata.ingress_global_timestamp);
}
table add_options_tbl{
    actions {
        add_options;
    }
    default_action :add_options();
}

action cal_minus() {
    subtract(md.t_minus,intrinsic_metadata.ingress_global_timestamp,options.option);
}
table cal_minus_tbl{
    actions {
        cal_minus;
    }
    default_action :cal_minus;
}

action remove() {
    remove_header(options);
}
table remove_tbl{
    actions {
        remove;
    }
    default_action : remove;
}


action report() {
    clone_ingress_pkt_to_egress(4,report_fields);
}
table report_tbl{
    actions {
        report;
    }
    default_action : report;
}


field_list report_fields {
    md.t_minus;
    intrinsic_metadata.egress_spec;
} 


control ingress{
    if(valid(tcp)&&((tcp.ctrl & 0b011) == 0b011)){ 
        if( intrinsic_metadata.egress_spec != 1 ){
            if(!valid(options)){
                /* record ingress timestamp of the request in the IP option */
                apply(add_options_tbl);
            }else{
                /* calculate the host-side latency */
                apply(cal_minus_tbl);
                if(md.t_minus > I){
                /*report latency data to the analyzer*/
                    apply(report_tbl); 
                }
                /*reset the IP option*/
                apply(remove_tbl);
            }
        }
    }
}


control egress{
}
