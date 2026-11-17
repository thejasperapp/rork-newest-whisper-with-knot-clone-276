import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { NotesAppIcon } from "./NotesAppIcon";

afterEach(cleanup);

describe("Notes app artwork", () => {
  it("uses the supplied light and dark files with complementary app-theme classes", () => {
    const { container } = render(<NotesAppIcon />);
    const images = container.querySelectorAll("img");
    expect(images).toHaveLength(2);
    expect(images[0]).toHaveAttribute("src", "/notes-app-light-20260926-v1.png");
    expect(images[0]).toHaveClass("block", "dark:hidden");
    expect(images[1]).toHaveAttribute("src", "/notes-app-dark-20260926-v8.png");
    expect(images[1]).toHaveClass("hidden", "dark:block");
    expect(container.firstElementChild).toHaveAttribute("aria-hidden", "true");
    for (const image of images) {
      expect(image).toHaveAttribute("alt", "");
      expect(image).toHaveClass("object-contain");
    }
  });

  it("supports the larger entry header without retaining the menu dimensions", () => {
    const { container } = render(<NotesAppIcon className="h-[52px] w-[52px] rounded-[13px]" />);
    expect(container.firstElementChild).toHaveClass("h-[52px]", "w-[52px]", "rounded-[13px]");
    expect(container.firstElementChild).not.toHaveClass("h-10", "w-10", "rounded-[11px]");
  });
});
