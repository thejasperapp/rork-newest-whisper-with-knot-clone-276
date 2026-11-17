import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { Switch } from "@/components/ui/switch";
import { pushPreferenceRequest, type PushField } from "@/lib/pushPreferences";
const rows: {field:PushField;title:string;subtitle:string}[] = [
 {field:"master_enabled",title:"Push notifications",subtitle:"Master switch for your account's device alerts"},
 {field:"quiet_mode",title:"Quiet mode",subtitle:"Silence alerts without changing categories"},
 {field:"dms",title:"Direct messages",subtitle:"Messages and group conversations"},
 {field:"mentions",title:"Mentions",subtitle:"Tags in posts, comments and Stories"},
 {field:"likes",title:"Likes",subtitle:"When someone likes your post"},
 {field:"comments",title:"Comments",subtitle:"Replies on your posts"},
 {field:"follows",title:"New followers",subtitle:"When someone follows you"},
 {field:"story_responses",title:"Story responses",subtitle:"Poll votes, ratings and replies"},
 {field:"new_posts",title:"Return-to-posting alerts",subtitle:"Occasional updates from followed contacts you interact with—not every post"},
];
/** Server preferences replace the old browser-only notification switches. */
export function RemotePushSettings(){const {user}=useAuth();return user?<AccountPushSettings key={user.id} owner={user.id}/>:null;}
function AccountPushSettings({owner}:{owner:string}){
 const cache=useQueryClient();const key=["device-push-preferences",owner];
 const query=useQuery({queryKey:key,queryFn:()=>pushPreferenceRequest(owner),retry:false,staleTime:0});
 const change=useMutation({mutationFn:({field,value}:{field:PushField;value:boolean})=>pushPreferenceRequest(owner,{field,value}),onSuccess:(data)=>cache.setQueryData(key,data)});
 const prefs=query.isError?undefined:query.data;
 return <div className="divide-y divide-border">
 {query.isPending?<p role="status" className="p-4 text-sm text-muted-foreground">Loading device preferences…</p>:null}
 {(query.isError||change.isError)&&<div role="alert" className="p-4 text-sm"><p>{change.isError?"Your last change wasn't confirmed. Refresh before trying again.":"Couldn't load preferences. No settings were changed."}</p><button type="button" className="min-h-11 font-semibold" onClick={()=>{change.reset();void query.refetch();}}>Refresh preferences</button></div>}
 {rows.map(row=>{const available=prefs!==undefined&&(row.field!=="new_posts"||prefs.new_posts!==undefined);const disabled=!available||query.isFetching||change.isPending||change.isError||(row.field!=="master_enabled"&&(prefs?.master_enabled===false||(row.field!=="quiet_mode"&&prefs?.quiet_mode===true)));return <div key={row.field} className="flex items-center gap-4 px-4 py-3"><div className="min-w-0 flex-1"><p id={`push-${row.field}`} className="text-sm font-semibold">{row.title}</p><p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">{row.field==="new_posts"&&!available?"Available after the notification service update":row.subtitle}</p></div><Switch aria-labelledby={`push-${row.field}`} checked={available&&(prefs[row.field]??row.field!=="quiet_mode")} disabled={disabled} onCheckedChange={value=>change.mutate({field:row.field,value})}/></div>;})}
 <p className="px-4 py-3 text-xs leading-relaxed text-muted-foreground">Changes apply after server confirmation. Your device's notification permission and focus mode still apply. This does not enable browser push.</p>
 </div>;
}
