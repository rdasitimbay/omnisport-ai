# Design System Specification: The Kinetic Lab

## 1. Overview & Creative North Star
This design system is built to transcend the standard utility of sports tracking. Our Creative North Star is **"The Kinetic Lab."** Unlike generic fitness apps that rely on heavy borders and static grids, this system treats the UI as a high-performance instrument—precise, fluid, and data-driven.

The aesthetic direction moves away from "app-like" templates toward a **High-End Editorial** experience. We achieve this through intentional asymmetry, massive typographic contrast, and a "No-Line" philosophy. By overlapping elements and utilizing varying surface depths, we create a sense of forward momentum and professional authority, mirroring the peak performance of the athletes using the platform.

---

## 2. Colors: Tonal Architecture
The palette is rooted in a dynamic sports blue, but its application must be sophisticated. We move beyond flat fills to create a "living" interface.

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders to define sections or cards. Hierarchy must be established exclusively through background color shifts.
*   **The Technique:** Use `surface-container-low` (#f3f4f5) for the main page background. Place `surface-container-lowest` (#ffffff) cards on top to create a perceived lift.
*   **Nesting:** For internal card sections, use `surface-container` (#edeeef) to "recess" secondary information, creating depth through subtraction rather than addition.

### Glass & Gradient Strategy
To avoid a "flat" out-of-the-box Material feel:
*   **Signature Gradients:** Use a subtle linear gradient (Top-Left to Bottom-Right) transitioning from `primary_container` (#0056b3) to `primary` (#003f87) for hero CTAs and high-impact data visualizations.
*   **Glassmorphism:** Floating action buttons (FABs) or top navigation bars should utilize `surface_container_lowest` at 85% opacity with a `20px` backdrop blur. This ensures the "Kinetic" energy of the background content is felt even when occluded.

---

## 3. Typography: Athletic Precision
The system utilizes a dual-font pairing to balance technical data with aggressive performance energy.

*   **Headlines (Manrope):** Chosen for its geometric, high-tech character. Use `display-lg` (3.5rem) and `headline-lg` (2rem) with tight letter-spacing (-0.02em) to create an authoritative, editorial impact.
*   **Body & Labels (Inter):** The industry standard for legibility. Inter handles the heavy lifting of performance metrics. 
*   **The Scale Logic:** Use "Extreme Contrast." Pair a `display-sm` headline directly with `label-md` metadata. This gap in scale creates a premium, designer-led feel rather than a generic vertical stack.

---

## 4. Elevation & Depth: Tonal Layering
Traditional shadows are often "dirty" and clutter a clean UI. We prioritize **Tonal Layering** to define the Z-axis.

*   **The Layering Principle:** 
    1.  **Level 0 (Base):** `surface` (#f8f9fa)
    2.  **Level 1 (Sections):** `surface-container-low` (#f3f4f5)
    3.  **Level 2 (Active Cards):** `surface-container-lowest` (#ffffff)
*   **Ambient Shadows:** Where floating elements are required (e.g., Modals), use a "Long-Soft" shadow: `box-shadow: 0 12px 40px rgba(0, 26, 64, 0.06)`. The tint is pulled from `on_primary_fixed` to ensure the shadow feels like a natural refraction of the environment.
*   **The Ghost Border:** If a boundary is required for accessibility, use `outline_variant` (#c2c6d4) at 15% opacity. It should be felt, not seen.

---

## 5. Components: Performance-Grade UI

### Action Buttons
*   **Primary:** Pill-shaped (`rounded-full`), using the signature Blue gradient. No border.
*   **Secondary:** `surface-container-high` background with `primary` text. This creates a "soft" button that doesn't compete with the main CTA.
*   **Interaction:** On press, the background should shift to `primary_fixed_dim`.

### Performance Cards
*   **Construction:** Card-based layouts must never use dividers. Separate content using the Spacing Scale (e.g., `8` (2rem) for section gaps and `4` (1rem) for internal grouping).
*   **Visual Soul:** Use `surface-container-highest` for small "tag" containers within cards to highlight key metrics (e.g., "BPM" or "Speed").

### Input Fields
*   **Style:** Minimalist. Use `surface-container-low` as the field fill with no border. On focus, transition the background to `surface-container-lowest` and add a 2px "Ghost Border" using the `primary` color.
*   **Typography:** Labels use `label-md` in `on_surface_variant`.

### Data Visualization (Specific to Sport-AI)
*   **The Metric Overlap:** Allow charts to bleed to the edge of cards. Use `primary` for positive trends and `tertiary` (#722b00) for alerts or areas needing focus.

---

## 6. Do’s and Don’ts

### Do:
*   **Embrace White Space:** Use the `12` (3rem) and `16` (4rem) spacing tokens frequently. "High-performance" requires room to breathe.
*   **Asymmetric Alignment:** Push some text elements to the far right while headers stay left to create an editorial "zigzag" that guides the eye.
*   **Use Intentional Depth:** Always ask "Which surface tier am I on?" before adding a shadow.

### Don’t:
*   **Don't use 1px Dividers:** Never use a line to separate two items in a list. Use a background color shift or a `1.5` (0.375rem) vertical gap.
*   **Don't use Pure Black:** Always use `on_surface` (#191c1d) for text to maintain a professional, high-end softness.
*   **Don't use Standard MD3 Corners:** While MD3 suggests varied rounding, this system leans into `xl` (0.75rem) for cards and `full` for buttons to maintain an "Energetic/Modern" vibe. Avoid `sm` or `none` unless for technical data tables.

---

## 7. Token Reference Summary
*   **Primary Action:** `#0056b3` (Primary Container)
*   **Base Canvas:** `#f8f9fa` (Surface)
*   **Card Base:** `#ffffff` (Surface Container Lowest)
*   **Text (High Emphasis):** `#191c1d` (On Surface)
*   **Rounding (Cards):** `0.75rem` (xl)
*   **Rounding (Buttons):** `9999px` (full)