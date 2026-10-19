#pragma once

#ifndef HV_STATICLIB
#define HV_STATICLIB
#endif

#ifdef _MSC_VER
#pragma warning(disable:4458)
#endif

#include <hv/requests.h>
#include <hv/HttpServer.h>
#include <hv/WebSocketClient.h>
#include <hv/WebSocketServer.h>

#include "daScript/simulate/simulate.h"
#include "native_binding.h"

namespace das {
    struct WebSocketAdmission;
inline Handle<hv::WebSocketClient> makeWebSocketClient( const void * pClass, const StructInfo * info, Context * context ) {
    using Fn=Handle<hv::WebSocketClient>(*)(const void *,const StructInfo *,Context *);
    static auto call=rx_native_aot::resolve<Fn>("makeWebSocketClient");
    return call(pClass,info,context);
}
inline int das_wsc_open( Handle<hv::WebSocketClient> h, const char* url ) {
    using Fn=int(*)(Handle<hv::WebSocketClient>,const char*);
    static auto call=rx_native_aot::resolve<Fn>("das_wsc_open");
    return call(h,url);
}
inline int das_wsc_send( Handle<hv::WebSocketClient> h, const char* msg ) {
    using Fn=int(*)(Handle<hv::WebSocketClient>,const char*);
    static auto call=rx_native_aot::resolve<Fn>("das_wsc_send");
    return call(h,msg);
}
inline int das_wsc_send_buf( Handle<hv::WebSocketClient> h, const char* msg, int32_t len, ws_opcode opcode ) {
    using Fn=int(*)(Handle<hv::WebSocketClient>,const char*,int32_t,ws_opcode);
    static auto call=rx_native_aot::resolve<Fn>("das_wsc_send_buf");
    return call(h,msg,len,opcode);
}
inline int das_wsc_close( Handle<hv::WebSocketClient> h ) {
    using Fn=int(*)(Handle<hv::WebSocketClient>);
    static auto call=rx_native_aot::resolve<Fn>("das_wsc_close");
    return call(h);
}
inline void das_hv_set_log_file( const char * path ) {
    using Fn=void(*)(const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_hv_set_log_file");
    return call(path);
}
inline bool das_wsc_is_connected( Handle<hv::WebSocketClient> h ) {
    using Fn=bool(*)(Handle<hv::WebSocketClient>);
    static auto call=rx_native_aot::resolve<Fn>("das_wsc_is_connected");
    return call(h);
}
inline void das_wsc_tick( Handle<hv::WebSocketClient> h ) {
    using Fn=void(*)(Handle<hv::WebSocketClient>);
    static auto call=rx_native_aot::resolve<Fn>("das_wsc_tick");
    return call(h);
}
inline Handle<hv::WebSocketServer> makeWebSocketServer( int port, int httpsPort, const char * pathToCert, const void * pClass, const StructInfo * info, Context * context, LineInfoArg * at ) {
    using Fn=Handle<hv::WebSocketServer>(*)(int,int,const char *,const void *,const StructInfo *,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("makeWebSocketServer");
    return call(port,httpsPort,pathToCert,pClass,info,context,at);
}
inline int das_wss_send( Handle<hv::WebSocketChannel> h, const char * msg, ws_opcode opcode, bool fin ) {
    using Fn=int(*)(Handle<hv::WebSocketChannel>,const char *,ws_opcode,bool);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_send");
    return call(h,msg,opcode,fin);
}
inline int das_wss_send_buf( Handle<hv::WebSocketChannel> h, const char * buf, int32_t len, ws_opcode opcode, bool fin ) {
    using Fn=int(*)(Handle<hv::WebSocketChannel>,const char *,int32_t,ws_opcode,bool);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_send_buf");
    return call(h,buf,len,opcode,fin);
}
inline int das_wss_send_fragment( Handle<hv::WebSocketChannel> h, const char * buf, int32_t len, int32_t fragment, ws_opcode opcode ) {
    using Fn=int(*)(Handle<hv::WebSocketChannel>,const char *,int32_t,int32_t,ws_opcode);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_send_fragment");
    return call(h,buf,len,fragment,opcode);
}
inline int das_wss_close_channel( Handle<hv::WebSocketChannel> h ) {
    using Fn=int(*)(Handle<hv::WebSocketChannel>);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_close_channel");
    return call(h);
}
inline bool das_wss_set_bind_host( Handle<hv::WebSocketServer> h, const char * host ) {
    using Fn=bool(*)(Handle<hv::WebSocketServer>,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_set_bind_host");
    return call(h,host);
}
inline bool das_wss_upgrade(Handle<hv::WebSocketServer> h, int timeout_ms, Lambda lmb, Context * context, LineInfoArg * at) {
    using Fn=bool(*)(Handle<hv::WebSocketServer>,int,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_upgrade");
    return call(h,timeout_ms,lmb,context,at);
}
inline int das_accept_websocket(Handle<WebSocketAdmission> admission, const char * protocol) {
    using Fn=int(*)(Handle<WebSocketAdmission>,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_accept_websocket");
    return call(admission,protocol);
}
inline int das_reject_websocket(Handle<WebSocketAdmission> admission, int status) {
    using Fn=int(*)(Handle<WebSocketAdmission>,int);
    static auto call=rx_native_aot::resolve<Fn>("das_reject_websocket");
    return call(admission,status);
}
inline bool das_wss_set_access_log(Handle<hv::WebSocketServer> h, bool enabled) {
    using Fn=bool(*)(Handle<hv::WebSocketServer>,bool);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_set_access_log");
    return call(h,enabled);
}
inline bool das_wss_set_limits(Handle<hv::WebSocketServer> h, int http_bytes, int ws_bytes, int events, int queue_bytes) {
    using Fn=bool(*)(Handle<hv::WebSocketServer>,int,int,int,int);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_set_limits");
    return call(h,http_bytes,ws_bytes,events,queue_bytes);
}
inline int das_wss_start( Handle<hv::WebSocketServer> h ) {
    using Fn=int(*)(Handle<hv::WebSocketServer>);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_start");
    return call(h);
}
inline int das_wss_bound_port( Handle<hv::WebSocketServer> h ) {
    using Fn=int(*)(Handle<hv::WebSocketServer>);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_bound_port");
    return call(h);
}
inline void das_wss_tick( Handle<hv::WebSocketServer> h ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_tick");
    return call(h);
}
inline int das_wss_stop( Handle<hv::WebSocketServer> h ) {
    using Fn=int(*)(Handle<hv::WebSocketServer>);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_stop");
    return call(h);
}
inline void das_wss_get( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_get");
    return call(h,url,lmb,context,at);
}
inline void das_wss_post( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_post");
    return call(h,url,lmb,context,at);
}
inline void das_wss_put( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_put");
    return call(h,url,lmb,context,at);
}
inline void das_wss_del( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_del");
    return call(h,url,lmb,context,at);
}
inline void das_wss_patch( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_patch");
    return call(h,url,lmb,context,at);
}
inline void das_wss_head( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_head");
    return call(h,url,lmb,context,at);
}
inline void das_wss_any( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_any");
    return call(h,url,lmb,context,at);
}
inline void das_wss_sse( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_sse");
    return call(h,url,lmb,context,at);
}
inline void das_wss_stream( Handle<hv::WebSocketServer> h, const char * url, Lambda lmb, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,Lambda,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_stream");
    return call(h,url,lmb,context,at);
}
inline void das_wss_static( Handle<hv::WebSocketServer> h, const char * path, const char * dir ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_static");
    return call(h,path,dir);
}
inline void das_wss_allow_cors( Handle<hv::WebSocketServer> h ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_allow_cors");
    return call(h);
}
inline void das_wss_set_document_root( Handle<hv::WebSocketServer> h, const char * dir ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_set_document_root");
    return call(h,dir);
}
inline void das_wss_set_home_page( Handle<hv::WebSocketServer> h, const char * filename ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_set_home_page");
    return call(h,filename);
}
inline void das_wss_set_index_of( Handle<hv::WebSocketServer> h, const char * dir ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_set_index_of");
    return call(h,dir);
}
inline void das_wss_set_error_page( Handle<hv::WebSocketServer> h, const char * filename ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_wss_set_error_page");
    return call(h,filename);
}
inline int das_writer_respond( Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w, int32_t status, const char * content_type, const char * body ) {
    using Fn=int(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *,int32_t,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_respond");
    return call(h,w,status,content_type,body);
}
inline int das_writer_end_headers( Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w, const char * key, const char * value ) {
    using Fn=int(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_end_headers");
    return call(h,w,key,value);
}
inline int das_writer_sse_event( Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w, const char * data, const char * event ) {
    using Fn=int(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_sse_event");
    return call(h,w,data,event);
}
inline int das_writer_write_chunked( Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w, const char * data ) {
    using Fn=int(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_write_chunked");
    return call(h,w,data);
}
inline void das_writer_set_keepalive_timeout( Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w, int32_t timeout_ms ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *,int32_t);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_set_keepalive_timeout");
    return call(h,w,timeout_ms);
}
inline int das_writer_serve_file_stream(Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w, const char * filepath, int64_t max_bytes) {
    using Fn=int(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *,const char *,int64_t);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_serve_file_stream");
    return call(h,w,filepath,max_bytes);
}
inline void das_writer_close( Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_close");
    return call(h,w);
}
inline void das_writer_release( Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w ) {
    using Fn=void(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_release");
    return call(h,w);
}
inline bool das_writer_is_connected( Handle<hv::WebSocketServer> h, hv::HttpResponseWriter * w ) {
    using Fn=bool(*)(Handle<hv::WebSocketServer>,hv::HttpResponseWriter *);
    static auto call=rx_native_aot::resolve<Fn>("das_writer_is_connected");
    return call(h,w);
}
inline http_status das_resp_string( HttpResponse * resp, const char * msg, http_status status ) {
    using Fn=http_status(*)(HttpResponse *,const char *,http_status);
    static auto call=rx_native_aot::resolve<Fn>("das_resp_string");
    return call(resp,msg,status);
}
inline http_status das_resp_json( HttpResponse * resp, const char * json_str, http_status status ) {
    using Fn=http_status(*)(HttpResponse *,const char *,http_status);
    static auto call=rx_native_aot::resolve<Fn>("das_resp_json");
    return call(resp,json_str,status);
}
inline http_status das_resp_redirect( HttpResponse * resp, const char * location, http_status status ) {
    using Fn=http_status(*)(HttpResponse *,const char *,http_status);
    static auto call=rx_native_aot::resolve<Fn>("das_resp_redirect");
    return call(resp,location,status);
}
inline http_status das_resp_file( HttpResponse * resp, const char * filepath ) {
    using Fn=http_status(*)(HttpResponse *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_resp_file");
    return call(resp,filepath);
}
inline http_status das_resp_data( HttpResponse * resp, const char * data, int32_t len, http_status status ) {
    using Fn=http_status(*)(HttpResponse *,const char *,int32_t,http_status);
    static auto call=rx_native_aot::resolve<Fn>("das_resp_data");
    return call(resp,data,len,status);
}
inline void das_resp_set_header( HttpResponse * resp, const char * key, const char * value ) {
    using Fn=void(*)(HttpResponse *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_resp_set_header");
    return call(resp,key,value);
}
inline void das_resp_set_content_type( HttpResponse * resp, const char * ct ) {
    using Fn=void(*)(HttpResponse *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_resp_set_content_type");
    return call(resp,ct);
}
inline int das_http_response_content_length( const HttpResponse & resp ) {
    using Fn=int(*)(const HttpResponse &);
    static auto call=rx_native_aot::resolve<Fn>("das_http_response_content_length");
    return call(resp);
}
inline void das_httpr_each_param( HttpRequest * req, const TBlock<void,const char *,const char *> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(HttpRequest *,const TBlock<void,const char *,const char *> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_each_param");
    return call(req,block,context,at);
}
inline void das_httpr_set_header( HttpRequest * req, const char * key, const char * value ) {
    using Fn=void(*)(HttpRequest *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_header");
    return call(req,key,value);
}
inline char * das_httpm_get_header( HttpMessage * msg, const char * key, Context * context, LineInfoArg * at ) {
    using Fn=char *(*)(HttpMessage *,const char *,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpm_get_header");
    return call(msg,key,context,at);
}
inline void das_httpm_each_header( HttpMessage * msg, const TBlock<void,const char *,const char *> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(HttpMessage *,const TBlock<void,const char *,const char *> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpm_each_header");
    return call(msg,block,context,at);
}
inline char * das_httpr_status_message( HttpResponse * resp, Context * context, LineInfoArg * at ) {
    using Fn=char *(*)(HttpResponse *,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_status_message");
    return call(resp,context,at);
}
inline char * das_httpr_get_param( HttpRequest * req, const char * key, Context * context, LineInfoArg * at ) {
    using Fn=char *(*)(HttpRequest *,const char *,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_get_param");
    return call(req,key,context,at);
}
inline void das_httpr_set_basic_auth( HttpRequest * req, const char * username, const char * password ) {
    using Fn=void(*)(HttpRequest *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_basic_auth");
    return call(req,username,password);
}
inline void das_httpr_set_bearer_token_auth( HttpRequest * req, const char * token ) {
    using Fn=void(*)(HttpRequest *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_bearer_token_auth");
    return call(req,token);
}
inline void das_httpr_set_timeout( HttpRequest * req, int sec ) {
    using Fn=void(*)(HttpRequest *,int);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_timeout");
    return call(req,sec);
}
inline void das_httpr_set_connect_timeout( HttpRequest * req, int sec ) {
    using Fn=void(*)(HttpRequest *,int);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_connect_timeout");
    return call(req,sec);
}
inline void das_httpr_allow_redirect( HttpRequest * req, bool on ) {
    using Fn=void(*)(HttpRequest *,bool);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_allow_redirect");
    return call(req,on);
}
inline void das_httpr_set_param( HttpRequest * req, const char * key, const char * value ) {
    using Fn=void(*)(HttpRequest *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_param");
    return call(req,key,value);
}
inline void das_httpr_set_content_type( HttpRequest * req, const char * ct ) {
    using Fn=void(*)(HttpRequest *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_content_type");
    return call(req,ct);
}
inline void das_req_GET( const char * url, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_GET");
    return call(url,block,context,at);
}
inline void das_req_GET_H( const char * url, const TTable<char *,char *> & tab, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_GET_H");
    return call(url,tab,block,context,at);
}
inline void das_req_POST( const char * url, const char * text, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_POST");
    return call(url,text,block,context,at);
}
inline void das_req_POST_H( const char * url, const char * text, const TTable<char *,char *> & tab, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_POST_H");
    return call(url,text,tab,block,context,at);
}
inline void das_req_POST_HF( const char * url, const char * text, const TTable<char *,char *> & tab, const TTable<char *,char *> & from, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TTable<char *,char *> &,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_POST_HF");
    return call(url,text,tab,from,block,context,at);
}
inline void das_req_PUT( const char * url, const char * text, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_PUT");
    return call(url,text,block,context,at);
}
inline void das_req_PUT_H( const char * url, const char * text, const TTable<char *,char *> & tab, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_PUT_H");
    return call(url,text,tab,block,context,at);
}
inline void das_req_PUT_HF( const char * url, const char * text, const TTable<char *,char *> & tab, const TTable<char *,char *> & from, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TTable<char *,char *> &,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_PUT_HF");
    return call(url,text,tab,from,block,context,at);
}
inline void das_req_PATCH( const char * url, const char * text, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_PATCH");
    return call(url,text,block,context,at);
}
inline void das_req_PATCH_H( const char * url, const char * text, const TTable<char *,char *> & tab, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_PATCH_H");
    return call(url,text,tab,block,context,at);
}
inline void das_req_PATCH_HF( const char * url, const char * text, const TTable<char *,char *> & tab, const TTable<char *,char *> & from, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const char *,const TTable<char *,char *> &,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_PATCH_HF");
    return call(url,text,tab,from,block,context,at);
}
inline void das_req_DELETE( const char * url, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_DELETE");
    return call(url,block,context,at);
}
inline void das_req_DELETE_H( const char * url, const TTable<char *,char *> & tab, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_DELETE_H");
    return call(url,tab,block,context,at);
}
inline void das_req_HEAD( const char * url, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_HEAD");
    return call(url,block,context,at);
}
inline void das_req_HEAD_H( const char * url, const TTable<char *,char *> & tab, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(const char *,const TTable<char *,char *> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_HEAD_H");
    return call(url,tab,block,context,at);
}
inline int das_req_REQUEST_CHECKED(HttpRequest * req, const char * ca_file, int max_response_bytes, const TBlock<void,TTemporary<HttpResponse*>> & block, Context * context, LineInfoArg * at) {
    using Fn=int(*)(HttpRequest *,const char *,int,const TBlock<void,TTemporary<HttpResponse*>> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_REQUEST_CHECKED");
    return call(req,ca_file,max_response_bytes,block,context,at);
}
inline void das_req_REQUEST( HttpRequest * req, const TBlock<void,HttpResponse*> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(HttpRequest *,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_REQUEST");
    return call(req,block,context,at);
}
inline void das_req_REQUEST_CB( HttpRequest * req, const TBlock<void,const uint8_t*,int32_t> & on_body, const TBlock<void,HttpResponse*> & on_complete, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(HttpRequest *,const TBlock<void,const uint8_t*,int32_t> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_REQUEST_CB");
    return call(req,on_body,on_complete,context,at);
}
inline void das_req_REQUEST_CB_S( HttpRequest * req, const TBlock<void,const char*> & on_body, const TBlock<void,HttpResponse*> & on_complete, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(HttpRequest *,const TBlock<void,const char*> &,const TBlock<void,HttpResponse*> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_req_REQUEST_CB_S");
    return call(req,on_body,on_complete,context,at);
}
inline void das_httpreq_add_cookie( HttpRequest * req, const char * name, const char * value ) {
    using Fn=void(*)(HttpRequest *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpreq_add_cookie");
    return call(req,name,value);
}
inline void das_httpreq_add_cookie_ex( HttpRequest * req, const char * name, const char * value, const char * domain, const char * path, int max_age, bool secure, bool httponly ) {
    using Fn=void(*)(HttpRequest *,const char *,const char *,const char *,const char *,int,bool,bool);
    static auto call=rx_native_aot::resolve<Fn>("das_httpreq_add_cookie_ex");
    return call(req,name,value,domain,path,max_age,secure,httponly);
}
inline char * das_httpreq_get_cookie( HttpRequest * req, const char * name, Context * context, LineInfoArg * at ) {
    using Fn=char *(*)(HttpRequest *,const char *,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpreq_get_cookie");
    return call(req,name,context,at);
}
inline void das_httpreq_each_cookie( HttpRequest * req, const TBlock<void,const char *,const char *> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(HttpRequest *,const TBlock<void,const char *,const char *> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpreq_each_cookie");
    return call(req,block,context,at);
}
inline void das_httpresp_add_cookie( HttpResponse * resp, const char * name, const char * value ) {
    using Fn=void(*)(HttpResponse *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpresp_add_cookie");
    return call(resp,name,value);
}
inline void das_httpresp_add_cookie_ex( HttpResponse * resp, const char * name, const char * value, const char * domain, const char * path, int max_age, bool secure, bool httponly ) {
    using Fn=void(*)(HttpResponse *,const char *,const char *,const char *,const char *,int,bool,bool);
    static auto call=rx_native_aot::resolve<Fn>("das_httpresp_add_cookie_ex");
    return call(resp,name,value,domain,path,max_age,secure,httponly);
}
inline char * das_httpresp_get_cookie( HttpResponse * resp, const char * name, Context * context, LineInfoArg * at ) {
    using Fn=char *(*)(HttpResponse *,const char *,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpresp_get_cookie");
    return call(resp,name,context,at);
}
inline void das_httpresp_each_cookie( HttpResponse * resp, const TBlock<void,const char *,const char *> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(HttpResponse *,const TBlock<void,const char *,const char *> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpresp_each_cookie");
    return call(resp,block,context,at);
}
inline void das_httpr_set_form_data( HttpRequest * req, const char * name, const char * value ) {
    using Fn=void(*)(HttpRequest *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_form_data");
    return call(req,name,value);
}
inline void das_httpr_set_form_file( HttpRequest * req, const char * name, const char * filepath ) {
    using Fn=void(*)(HttpRequest *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_form_file");
    return call(req,name,filepath);
}
inline char * das_httpreq_get_form_data( HttpRequest * req, const char * name, Context * context, LineInfoArg * at ) {
    using Fn=char *(*)(HttpRequest *,const char *,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpreq_get_form_data");
    return call(req,name,context,at);
}
inline int das_httpreq_save_form_file( HttpRequest * req, const char * name, const char * path ) {
    using Fn=int(*)(HttpRequest *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpreq_save_form_file");
    return call(req,name,path);
}
inline void das_httpreq_each_form_field( HttpRequest * req, const TBlock<void,const char *,const char *,const char *> & block, Context * context, LineInfoArg * at ) {
    using Fn=void(*)(HttpRequest *,const TBlock<void,const char *,const char *,const char *> &,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpreq_each_form_field");
    return call(req,block,context,at);
}
inline void das_httpr_set_url_encoded( HttpRequest * req, const char * key, const char * value ) {
    using Fn=void(*)(HttpRequest *,const char *,const char *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpr_set_url_encoded");
    return call(req,key,value);
}
inline char * das_httpreq_get_url_encoded( HttpRequest * req, const char * key, Context * context, LineInfoArg * at ) {
    using Fn=char *(*)(HttpRequest *,const char *,Context *,LineInfoArg *);
    static auto call=rx_native_aot::resolve<Fn>("das_httpreq_get_url_encoded");
    return call(req,key,context,at);
}
}
namespace das { template<> inline bool das_handle_is_alive<hv::WebSocketClient>(Handle<hv::WebSocketClient> h) {
    using Fn=bool(*)(Handle<hv::WebSocketClient>);
    static auto call=rx_native_aot::resolve<Fn>("das_handle_is_alive","WebSocketClient");
    return call(h);
} }
namespace das { template<> inline bool das_handle_release<hv::WebSocketClient>(Handle<hv::WebSocketClient> h) {
    using Fn=bool(*)(Handle<hv::WebSocketClient>);
    static auto call=rx_native_aot::resolve<Fn>("das_handle_release","WebSocketClient");
    return call(h);
} }
namespace das { template<> inline bool das_handle_is_alive<hv::WebSocketServer>(Handle<hv::WebSocketServer> h) {
    using Fn=bool(*)(Handle<hv::WebSocketServer>);
    static auto call=rx_native_aot::resolve<Fn>("das_handle_is_alive","WebSocketServer");
    return call(h);
} }
namespace das { template<> inline bool das_handle_release<hv::WebSocketServer>(Handle<hv::WebSocketServer> h) {
    using Fn=bool(*)(Handle<hv::WebSocketServer>);
    static auto call=rx_native_aot::resolve<Fn>("das_handle_release","WebSocketServer");
    return call(h);
} }
namespace das { template<> inline bool das_handle_is_alive<hv::WebSocketChannel>(Handle<hv::WebSocketChannel> h) {
    using Fn=bool(*)(Handle<hv::WebSocketChannel>);
    static auto call=rx_native_aot::resolve<Fn>("das_handle_is_alive","WebSocketChannel");
    return call(h);
} }
namespace das { template<> inline bool das_handle_release<hv::WebSocketChannel>(Handle<hv::WebSocketChannel> h) {
    using Fn=bool(*)(Handle<hv::WebSocketChannel>);
    static auto call=rx_native_aot::resolve<Fn>("das_handle_release","WebSocketChannel");
    return call(h);
} }
namespace das { template<> inline bool das_handle_is_alive<das::WebSocketAdmission>(Handle<das::WebSocketAdmission> h) {
    using Fn=bool(*)(Handle<das::WebSocketAdmission>);
    static auto call=rx_native_aot::resolve<Fn>("das_handle_is_alive","WebSocketAdmission");
    return call(h);
} }
namespace das { template<> inline bool das_handle_release<das::WebSocketAdmission>(Handle<das::WebSocketAdmission> h) {
    using Fn=bool(*)(Handle<das::WebSocketAdmission>);
    static auto call=rx_native_aot::resolve<Fn>("das_handle_release","WebSocketAdmission");
    return call(h);
} }

#include "native_types.h"
