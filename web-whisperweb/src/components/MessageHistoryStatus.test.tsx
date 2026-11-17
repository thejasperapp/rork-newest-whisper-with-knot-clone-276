import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MessageHistoryStatus } from "./MessageHistoryStatus";
afterEach(cleanup);

describe("member-facing history status", () => {
  it("renders no manual pagination or technical controls while idle", () => {
    const { container } = render(<MessageHistoryStatus loading={false} failure={null} onRetry={vi.fn()} />);
    expect(container.textContent).toBe("");
    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.queryByRole("status")).toBeNull();
  });
  it("uses accessible progress without exposing a pagination button", () => {
    render(<MessageHistoryStatus loading failure={null} onRetry={vi.fn()} />);
    expect(screen.getByRole("status", { name: "Loading messages" })).toBeTruthy();
    expect(screen.queryByRole("button")).toBeNull();
  });
  it("offers a deliberate retry with member-friendly earlier-history copy", () => {
    const retry = vi.fn();
    render(<MessageHistoryStatus loading={false} failure="earlier" onRetry={retry} />);
    expect(screen.getByText("Earlier messages are unavailable for a moment.")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(retry).toHaveBeenCalledTimes(1);
  });
  it("prevents repeated retries while a refresh is in progress", () => {
    const retry = vi.fn();
    render(<MessageHistoryStatus loading failure="refresh" onRetry={retry} />);
    expect(screen.getByText("Messages couldn’t refresh just now.")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(retry).not.toHaveBeenCalled();
  });
});
