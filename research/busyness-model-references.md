# Busyness Estimation Model — Research References

References used to design the Gaussian temporal busyness model in `backend/lambda/src/signals/foursquare.ts`.

## Core Algorithm: Sum of Gaussians

The model treats each popular time window as a Gaussian bell curve. Busyness at any time is:

```
score = popularity × dayMultiplier × Σ gaussian(t, center_k, width_k)
```

## Academic Papers

- **Predicting Temporal Activity Patterns of New Venues**
  EPJ Data Science, 2018. Uses Gaussian Process regression with RBF kernels on Foursquare check-in data.
  https://epjdatascience.springeropen.com/articles/10.1140/epjds/s13688-018-0142-z
  https://pmc.ncbi.nlm.nih.gov/articles/PMC6448359/

## Google Popular Times (Methodology)

- **Google Maps Blog — Popular Times & Live Busyness**
  How Google uses aggregated anonymized Location History to build hourly busyness profiles (0–100 scale relative to venue's own weekly peak).
  https://blog.google/products/maps/maps101-popular-times-and-live-busyness-information/

- **Google Business Profile — About Popular Times**
  Official documentation on how Popular Times data is generated and displayed.
  https://support.google.com/business/answer/6263531

- **How Does Google Popular Times Work? (UC Berkeley)**
  Technical analysis of the Popular Times algorithm, including differential privacy and relative scoring.
  https://stat198-spring18.github.io/blog/2018/04/25/how-does-google-popular-times-work

## Industry Tools & APIs

- **BestTime.app API Documentation**
  Commercial venue busyness forecasting API. Uses hourly percentages (0–100%) relative to weekly peak, similar to Google's approach.
  https://documentation.besttime.app/

- **Placer.ai — Foot Traffic Analytics**
  Enterprise foot traffic analytics from mobile SDK data. Reference for day-of-week multiplier patterns.
  https://www.placer.ai/foot-traffic-analytics

- **populartimes (Python library)**
  Open-source library for scraping Google Popular Times data. Useful reference for data structure and patterns.
  https://github.com/m-wrzr/populartimes

## Mathematical Foundations

- **Gaussian Function — Wikipedia**
  Mathematical definition and properties of the Gaussian/normal distribution used in the model.
  https://en.wikipedia.org/wiki/Gaussian_function

- **Gaussian Mixture Models for Time Series**
  GMM approach for temporal pattern modeling.
  https://link.springer.com/chapter/10.1007/978-3-642-41398-8_15

- **Smoothstep Interpolation — Wikipedia**
  Comparison of interpolation methods (linear, cosine, smoothstep, Gaussian). Gaussian was chosen for statistical grounding.
  https://en.wikipedia.org/wiki/Smoothstep

- **Simple Interpolation Methods Compared**
  Practical comparison of cosine, smoothstep, and other interpolation curves.
  https://codeplea.com/simple-interpolation

- **MATLAB Gaussian Model Fitting**
  Reference implementation for fitting Gaussian curves to temporal data.
  https://www.mathworks.com/help/curvefit/gaussian.html

## Key Design Decisions

1. **Why Gaussian over linear interpolation:** Gaussian curves naturally model crowd arrival/departure patterns — gradual ramp-up, peak, gradual taper. No artificial edge zones needed.
2. **sigma = windowDuration / 4:** Ensures 95% of the bell curve falls within the popular window (2-sigma rule).
3. **Day-of-week multipliers:** Even with per-day popular windows from Foursquare, the *intensity* of a Friday peak differs from a Tuesday peak. Multipliers derived from industry foot traffic data.
4. **Sum (not max) of Gaussians:** Overlapping windows (e.g., late lunch + early dinner) naturally combine by addition, matching real-world crowd behavior.
