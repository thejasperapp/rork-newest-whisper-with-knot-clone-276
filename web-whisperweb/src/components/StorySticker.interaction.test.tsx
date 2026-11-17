import { afterEach, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { StorySticker } from "./StorySticker";
import type { StorySticker as Sticker } from "@/lib/storyStickers";
afterEach(cleanup);
const base: Sticker = { id: "fixture", kind: "question", x: .5, y: .5, scale: 1, rotation: 0, text: "Ask me" };
it("opens a question response from the published sticker", () => {
  const tap = vi.fn(); render(<StorySticker sticker={base} interactive onTap={tap} />);
  fireEvent.click(screen.getByRole("button")); expect(tap).toHaveBeenCalledOnce();
});
it("opens the slider response instead of a dead inline drag", () => {
  const tap = vi.fn(); render(<StorySticker sticker={{...base, kind: "slider"}} interactive onTap={tap} />);
  fireEvent.click(screen.getByRole("button")); expect(tap).toHaveBeenCalledOnce();
});
it("does not enable owner voting", () => {
  const tap = vi.fn(); render(<StorySticker sticker={base} interactive={false} onTap={tap} />);
  fireEvent.click(screen.getByText("Ask me")); expect(tap).not.toHaveBeenCalled();
});
