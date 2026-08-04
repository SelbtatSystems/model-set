---
name: data-visualization-typescript
description: Chart selection guidance, TypeScript visualization code patterns, design principles, and accessibility considerations for creating effective data visualizations.
---

# Data Visualization Skill

Use this skill when creating, reviewing, or improving data visualizations. Prefer clear chart choices, accessible design, and concise TypeScript examples that can run in a browser-based app, dashboard, or static HTML report.

## Core Principles

- Start with the question the chart must answer.
- Choose the simplest chart that makes the relationship obvious.
- Make the title state the insight, not just the chart type.
- Use color to encode meaning, not decoration.
- Prefer direct labels and annotations over overloaded legends.
- Include units, source, date range, and relevant filters.
- Make the chart understandable without relying on color alone.

## Chart Selection Guide

### Choose by Data Relationship

| What you are showing | Best chart | Alternatives |
|---|---|---|
| Trend over time | Line chart | Area chart if showing cumulative totals or composition |
| Comparison across categories | Vertical bar chart | Horizontal bar for many categories, lollipop chart |
| Ranking | Horizontal bar chart | Dot plot, slope chart for comparing two periods |
| Part-to-whole composition | Stacked bar chart | Treemap for hierarchy, waffle chart |
| Composition over time | Stacked area chart | 100% stacked bar when proportions matter most |
| Distribution | Histogram | Box plot, violin plot, strip plot |
| Correlation between two variables | Scatter plot | Bubble chart when adding a third metric as size |
| Correlation across many variables | Heatmap / correlation matrix | Pair plot |
| Geographic patterns | Choropleth map | Bubble map, hex map |
| Flow or process | Sankey diagram | Funnel chart for sequential stages |
| Relationship network | Network graph | Chord diagram |
| Performance versus target | Bullet chart | Gauge for one single KPI only |
| Multiple KPIs at once | Small multiples | Dashboard with separate focused charts |

### When Not to Use Certain Charts

- **Pie charts:** Avoid unless there are fewer than 6 categories and rough proportions matter more than exact comparison. Use a bar chart for clearer comparisons.
- **3D charts:** Never use them. They distort perception and add no useful information.
- **Dual-axis charts:** Use cautiously. They can imply false correlation. Label both axes clearly if unavoidable.
- **Stacked bars with many categories:** Hard to compare middle segments. Use grouped bars, small multiples, or a table.
- **Donut charts:** Same issues as pie charts. Use only for very simple single-KPI display.

## TypeScript Visualization Code Patterns

The examples below use TypeScript with [Observable Plot](https://observablehq.com/plot/) for concise, accessible SVG charts. Use D3 only when lower-level customization is required.

### Setup

```bash
npm install @observablehq/plot d3
npm install -D typescript @types/d3
```

```ts
import * as Plot from "@observablehq/plot";
import * as d3 from "d3";

export type TimeSeriesRow = {
  date: Date;
  category: string;
  value: number;
};

export type CategoryMetricRow = {
  category: string;
  metric: number;
};

export type HeatmapRow = {
  rowDim: string;
  colDim: string;
  metric: number;
};

export const PALETTE_CATEGORICAL = [
  "#4C72B0",
  "#DD8452",
  "#55A868",
  "#C44E52",
  "#8172B3",
  "#937860",
] as const;

export const PALETTE_SEQUENTIAL = "YlOrRd";
export const PALETTE_DIVERGING = "RdBu";

export function appendChart(target: HTMLElement, chart: SVGSVGElement): void {
  target.replaceChildren(chart);
}
```

### Shared Figure Helper

Use a `<figure>` wrapper so the visualization has a semantic caption and can be paired with a table alternative.

```ts
export function renderFigure(options: {
  target: HTMLElement;
  chart: SVGSVGElement;
  caption: string;
  altText: string;
}): void {
  const figure = document.createElement("figure");
  const caption = document.createElement("figcaption");

  figure.setAttribute("role", "img");
  figure.setAttribute("aria-label", options.altText);
  caption.textContent = options.caption;

  figure.append(options.chart, caption);
  options.target.replaceChildren(figure);
}
```

## Line Chart: Time Series

Use for trends over time. Keep the x-axis chronological and avoid overloading the chart with too many series.

```ts
export function createLineChart(data: TimeSeriesRow[]): SVGSVGElement {
  return Plot.plot({
    width: 900,
    height: 480,
    marginLeft: 64,
    marginBottom: 48,
    title: "Metric increased steadily across the selected period",
    subtitle: "Grouped by category",
    x: {
      label: "Date",
      type: "time",
      grid: true,
    },
    y: {
      label: "Value",
      grid: true,
      nice: true,
    },
    color: {
      legend: true,
      range: PALETTE_CATEGORICAL,
    },
    marks: [
      Plot.lineY(data, {
        x: "date",
        y: "value",
        stroke: "category",
        strokeWidth: 2,
        tip: true,
      }),
      Plot.dot(data, {
        x: "date",
        y: "value",
        stroke: "category",
        fill: "white",
        r: 2.5,
        tip: true,
      }),
      Plot.ruleY([0]),
    ],
  }) as SVGSVGElement;
}
```

## Bar Chart: Category Comparison

Use horizontal bars when labels are long or when the chart is a ranking.

```ts
export function createHorizontalBarChart(data: CategoryMetricRow[]): SVGSVGElement {
  const sorted = [...data].sort((a, b) => d3.ascending(a.metric, b.metric));

  return Plot.plot({
    width: 900,
    height: Math.max(360, sorted.length * 34),
    marginLeft: 160,
    marginRight: 80,
    title: "Top categories ranked by metric value",
    x: {
      label: "Metric value",
      grid: true,
      tickFormat: formatNumber,
    },
    y: {
      label: null,
      domain: sorted.map((d) => d.category),
    },
    marks: [
      Plot.barX(sorted, {
        y: "category",
        x: "metric",
        fill: PALETTE_CATEGORICAL[0],
        tip: true,
      }),
      Plot.text(sorted, {
        y: "category",
        x: "metric",
        text: (d) => formatNumber(d.metric),
        dx: 8,
        textAnchor: "start",
      }),
      Plot.ruleX([0]),
    ],
  }) as SVGSVGElement;
}
```

## Histogram: Distribution

Use for the shape, spread, and skew of numeric data. Add mean or median lines only when they help the interpretation.

```ts
export function createHistogram(values: number[]): SVGSVGElement {
  const mean = d3.mean(values) ?? 0;
  const median = d3.median(values) ?? 0;

  return Plot.plot({
    width: 900,
    height: 480,
    marginLeft: 64,
    title: "Distribution of values with mean and median markers",
    x: {
      label: "Value",
      grid: true,
    },
    y: {
      label: "Frequency",
      grid: true,
    },
    marks: [
      Plot.rectY(values, Plot.binX({ y: "count" }, {
        x: (d) => d,
        thresholds: 30,
        fill: PALETTE_CATEGORICAL[0],
        inset: 0.5,
        tip: true,
      })),
      Plot.ruleX([mean], {
        stroke: "#C44E52",
        strokeDasharray: "4,4",
        strokeWidth: 2,
      }),
      Plot.ruleX([median], {
        stroke: "#55A868",
        strokeDasharray: "2,4",
        strokeWidth: 2,
      }),
      Plot.text([{ x: mean, label: `Mean: ${formatNumber(mean)}` }], {
        x: "x",
        y: 0,
        text: "label",
        dy: -12,
        textAnchor: "middle",
      }),
    ],
  }) as SVGSVGElement;
}
```

## Heatmap

Use heatmaps for dense matrices, such as metric values across two categorical dimensions or correlation matrices.

```ts
export function createHeatmap(data: HeatmapRow[]): SVGSVGElement {
  return Plot.plot({
    width: 900,
    height: 620,
    marginLeft: 120,
    marginBottom: 88,
    title: "Metric intensity by row and column dimension",
    x: {
      label: "Column dimension",
      tickRotate: -35,
    },
    y: {
      label: "Row dimension",
    },
    color: {
      scheme: "YlOrRd",
      label: "Metric value",
      legend: true,
    },
    marks: [
      Plot.cell(data, {
        x: "colDim",
        y: "rowDim",
        fill: "metric",
        inset: 0.5,
        tip: true,
      }),
      Plot.text(data, {
        x: "colDim",
        y: "rowDim",
        text: (d) => formatNumber(d.metric),
        fill: (d) => d.metric > d3.median(data, (row) => row.metric)! ? "white" : "black",
        fontSize: 10,
      }),
    ],
  }) as SVGSVGElement;
}
```

## Small Multiples

Use small multiples when comparing many categories with the same structure. Keep scales consistent when comparison matters.

```ts
export function createSmallMultiples(data: TimeSeriesRow[]): SVGSVGElement {
  return Plot.plot({
    width: 960,
    height: 720,
    marginLeft: 56,
    marginBottom: 48,
    title: "Trends by category",
    facet: {
      data,
      x: "category",
      columns: 3,
    },
    x: {
      label: "Date",
      type: "time",
      grid: true,
    },
    y: {
      label: "Value",
      grid: true,
      nice: true,
    },
    marks: [
      Plot.lineY(data, {
        x: "date",
        y: "value",
        stroke: PALETTE_CATEGORICAL[0],
        strokeWidth: 2,
        tip: true,
      }),
      Plot.ruleY([0]),
    ],
  }) as SVGSVGElement;
}
```

## Scatter Plot: Correlation

Use scatter plots for relationships between two numeric variables. Add size or color only when the extra variable is necessary.

```ts
type ScatterRow = {
  metricA: number;
  metricB: number;
  category: string;
  name: string;
  sizeMetric?: number;
};

export function createScatterPlot(data: ScatterRow[]): SVGSVGElement {
  return Plot.plot({
    width: 900,
    height: 520,
    marginLeft: 64,
    title: "Relationship between Metric A and Metric B",
    x: {
      label: "Metric A",
      grid: true,
      nice: true,
    },
    y: {
      label: "Metric B",
      grid: true,
      nice: true,
    },
    color: {
      legend: true,
      range: PALETTE_CATEGORICAL,
    },
    r: {
      range: [3, 16],
    },
    marks: [
      Plot.dot(data, {
        x: "metricA",
        y: "metricB",
        stroke: "category",
        fill: "category",
        fillOpacity: 0.65,
        r: "sizeMetric",
        tip: true,
      }),
      Plot.linearRegressionY(data, {
        x: "metricA",
        y: "metricB",
        stroke: "black",
        strokeDasharray: "4,4",
      }),
    ],
  }) as SVGSVGElement;
}
```

## Number Formatting Helpers

Use compact formatting for chart labels. Keep full precision in tooltips or companion tables when needed.

```ts
export type NumberFormatType = "number" | "currency" | "percent";

export function formatNumber(value: number, type: NumberFormatType = "number"): string {
  if (!Number.isFinite(value)) return "—";

  if (type === "percent") {
    return `${value.toFixed(1)}%`;
  }

  const abs = Math.abs(value);
  const prefix = type === "currency" ? "$" : "";
  const sign = value < 0 ? "-" : "";
  const normalized = Math.abs(value);

  if (abs >= 1_000_000_000) return `${sign}${prefix}${(normalized / 1_000_000_000).toFixed(1)}B`;
  if (abs >= 1_000_000) return `${sign}${prefix}${(normalized / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `${sign}${prefix}${(normalized / 1_000).toFixed(1)}K`;

  return `${sign}${prefix}${normalized.toLocaleString(undefined, {
    maximumFractionDigits: 0,
  })}`;
}

export function formatDate(value: Date): string {
  return new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(value);
}
```

## Interactive Charts with Plotly.js

Use Plotly when users need hover, zoom, pan, export controls, or quick interactive dashboards. Prefer static SVG charts for reports, PDFs, and high-performance pages.

```bash
npm install plotly.js-dist-min
npm install -D @types/plotly.js
```

```ts
import Plotly, { Data, Layout } from "plotly.js-dist-min";

export async function renderInteractiveLineChart(
  target: HTMLDivElement,
  data: TimeSeriesRow[],
): Promise<void> {
  const categories = Array.from(new Set(data.map((d) => d.category)));

  const traces: Data[] = categories.map((category) => {
    const rows = data.filter((d) => d.category === category);

    return {
      type: "scatter",
      mode: "lines+markers",
      name: category,
      x: rows.map((d) => d.date),
      y: rows.map((d) => d.value),
      hovertemplate: "%{x|%Y-%m-%d}<br>%{y:,}<extra>%{fullData.name}</extra>",
    };
  });

  const layout: Partial<Layout> = {
    title: { text: "Interactive metric trend" },
    xaxis: { title: { text: "Date" } },
    yaxis: { title: { text: "Metric value" } },
    hovermode: "x unified",
    legend: { orientation: "h" },
    margin: { l: 64, r: 32, t: 72, b: 56 },
  };

  await Plotly.newPlot(target, traces, layout, {
    responsive: true,
    displaylogo: false,
  });
}
```

## Design Principles

### Color

- Use color purposefully. Color should encode data, not decorate the page.
- Highlight the story. Use one accent color for the key insight and neutral colors for context.
- Sequential data: use a single-hue light-to-dark gradient.
- Diverging data: use a two-hue gradient with a neutral midpoint when the midpoint has meaning.
- Categorical data: use distinct hues and avoid more than 6–8 categories.
- Avoid red/green-only encodings. Use blue/orange or add labels, patterns, or shapes.

### Typography

- Title states the insight: “Revenue grew 23% YoY” is better than “Revenue by Month”.
- Subtitle adds context: date range, filters, source, and sample definition.
- Axis labels must be readable. Avoid 90-degree rotation when shortening or wrapping is possible.
- Data labels add precision. Use them for key points, not every point in a crowded chart.
- Use annotations to explain important outliers, inflection points, or thresholds.

### Layout

- Reduce chart junk: remove unnecessary gridlines, borders, shadows, and backgrounds.
- Sort meaningfully: usually by value, unless there is a natural order such as months or process stages.
- Use an appropriate aspect ratio: time series are usually wider than tall; comparisons can be more square.
- Leave white space. Do not cram multiple charts together.
- Keep legends close to the data or directly label series when possible.

### Accuracy

- Bar charts must start at zero. A bar from 95 to 100 exaggerates a small difference.
- Line charts may use non-zero baselines when the variation itself is the focus.
- Use consistent scales across panels when comparing small multiples.
- Show uncertainty with error bars, confidence intervals, bands, or ranges when data is uncertain.
- Label axes with units. Never make the reader guess what the numbers mean.

## Accessibility Considerations

### Color Blindness

- Never rely on color alone to distinguish series.
- Add pattern fills, line styles, symbols, direct labels, or annotations.
- Test with a colorblind simulator such as Coblis or Sim Daltonism.
- Use colorblind-friendly palettes, but still add non-color encodings when distinction is important.

### Screen Readers

- Wrap charts in semantic containers such as `<figure>` and `<figcaption>`.
- Add meaningful `aria-label` text describing the key finding.
- Provide a data table alternative for charts that support decisions or reporting.
- Use semantic titles, labels, and source notes.

### General Accessibility

- Ensure sufficient contrast between marks, labels, and background.
- Use at least 10pt-equivalent text for labels and 12pt-equivalent text for titles.
- Do not convey important information only through spatial position.
- Check that the chart still works in grayscale or when printed.

## Accessibility Checklist

Before sharing a visualization, confirm:

- [ ] The chart works without color because labels, patterns, symbols, or line styles distinguish series.
- [ ] Text is readable at standard zoom level.
- [ ] The title describes the insight, not just the data.
- [ ] Axes are labeled with units.
- [ ] The legend is clear and does not obscure the data.
- [ ] The data source and date range are noted.
- [ ] Important assumptions, filters, and exclusions are visible.
- [ ] A table or machine-readable data alternative is available when needed.

## Recommended Workflow for Agents

1. Identify the user’s analytical question.
2. Determine the data relationship: trend, comparison, ranking, distribution, correlation, composition, geography, flow, or KPI.
3. Choose the simplest chart that answers that question.
4. Create a TypeScript visualization with clear typing and reusable formatting helpers.
5. Add a title that states the insight.
6. Add labels, units, source, and date range.
7. Check accessibility before final delivery.
8. Prefer SVG/static charts for reports and HTML/Plotly charts for exploration.
