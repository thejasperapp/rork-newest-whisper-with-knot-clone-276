import React from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import Messages from "../src/pages/Messages";
import { Layout } from "../src/components/Layout";
import "../src/index.css";
const cache = new QueryClient({defaultOptions:{queries:{retry:false},mutations:{retry:false}}});
createRoot(document.getElementById("root")!).render(<QueryClientProvider client={cache}><MemoryRouter initialEntries={["/messages"]}><Layout><Messages/></Layout></MemoryRouter></QueryClientProvider>);
