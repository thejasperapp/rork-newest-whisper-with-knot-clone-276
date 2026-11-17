import { useState } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { StoryViewer, type StoryGroup } from "../src/components/StoryViewer";
import type { WhisperStory } from "../src/lib/types";
import "../src/index.css";
const story: WhisperStory = { id: "story-one", user_id: "author", username: "author", image_url: "/fixture-photo.svg", caption: "First story", created_at: new Date().toISOString(), expires_at: new Date(Date.now()+86400000).toISOString(), metadata: JSON.stringify({referenceStageWidth:390,stickers:[{id:"question",kind:"question",x:.5,y:.5,scale:1,rotation:0,text:"Ask me"}]}), music_url:null,music_title:null,music_artist:null,music_artwork:null };
const groups: StoryGroup[] = [{userId:"author",username:"author",avatarUrl:null,stories:[story,{...story,id:"story-two",caption:"Second story",metadata:null}]}];
function Fixture(){ const [open,setOpen]=useState<boolean>(true);return open ? <StoryViewer groups={groups} startGroup={0} onClose={()=>setOpen(false)} me={{id:"viewer",username:"viewer"}} /> : <p>Closed</p>; }
createRoot(document.getElementById("root")!).render(<QueryClientProvider client={new QueryClient({defaultOptions:{queries:{retry:false}}})}><MemoryRouter><Fixture /></MemoryRouter></QueryClientProvider>);
