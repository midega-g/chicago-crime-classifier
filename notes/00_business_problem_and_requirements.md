# Business Problem

## Executive Summary

In the City of Chicago, the Chicago Police Department (CPD) processes a high volume of reported crime incidents—approximately 300,000 annually based on historical trends from the Crimes-2001 to Present dataset—while grappling with persistent challenges in resource allocation, clearance rates, and public trust. With overall arrest rates hovering around 10-16% across crime types (e.g., ~14% for violent crimes in 2024), many incidents remain unresolved, leading to operational inefficiencies, escalating costs, and community perceptions of inadequate response.

This binary arrest outcome prediction classifier addresses these issues by leveraging publicly available CPD data to forecast arrest likelihood in real-time, enabling proactive triage that optimizes patrols, reduces unnecessary deployments, and promotes bias-aware decision-making. Built on the open [Crimes-2001 to Present dataset](https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/about_data) (updated daily as of October 11, 2025, excluding the most recent seven days), the model supports evidence-based policing while adhering to strict privacy and accuracy disclaimers.

### Core Problem Addressed

Urban law enforcement agencies like CPD operate under severe constraints: a workforce of over 12,000 officers managing diverse beats across 22 districts, amid budget pressures and rising expectations for transparency. In 2024, Chicago recorded 28,443 violent crimes alone (a slight decline from 2023 but still elevated compared to pre-pandemic levels), with property crimes and other incidents pushing the total reported caseload to historic highs in certain categories like aggravated assaults (up to 20-year peaks). Key pain points include:

- **Low Clearance Rates:** Arrests occur in only 10-16% of cases, with violent crime arrests at ~1-in-7 (14%) and homicide clearances at 56% (the highest since 2015 but still suboptimal). This results in backlog, offender recidivism, and underreporting (e.g., due to perceived inefficacy).
- **Resource Inefficiencies:** Reactive dispatching leads to overcommitment on low-yield calls, contributing to overtime spikes (e.g., \$273.8M budgeted at \$100M in 2024) and officer burnout.
- **Equity Gaps:** Disparities in response times and arrests by district, community area, or demographics (e.g., higher violent crime in South/West Sides) exacerbate inequities, eroding trust in high-crime neighborhoods.
- **Data and Systemic Limitations:** Preliminary incident data from the CLEAR system may change post-investigation, addresses are block-level only for victim privacy, and there's no guarantee of completeness or timeliness—prohibiting exact address derivations or time-series comparisons without caveats.

These factors drive annual costs exceeding hundreds of millions in personnel, investigations, and lost productivity, while failing to deter crime trends (e.g., shootings down 7% in 2024 but lethality up 44.9%).

## Argument for the Binary Arrest Prediction Classifier

This supervised machine learning model—targeting the "Arrest" column (Yes/No)—uses incident features like Date (for temporal patterns), IUCR/Primary Type (crime severity), Location Description, Domestic indicator, and geospatial elements (District/Beat/Community Area) to predict arrest probability upon report intake. Trained on ~8.4M historical records (2001-present, sampled for recency e.g., 2015+), it transitions from reactive to predictive policing, scoring incidents for triage:

- **Real-Time Prioritization:** High-probability cases (>70% threshold) routed to rapid-response units; low ones deprioritized for community follow-up, potentially reducing dispatch volume by 15-20% based on analogous AI integrations in urban departments.
- **Efficiency Gains:** Feature engineering (e.g., hour-of-day from Date, target-encoded Location Description) enables AUC-ROC >0.75 validation, minimizing false positives and supporting chronological train/test splits to avoid leakage.
- **Bias and Equity Safeguards:** Post-hoc audits via SHAP values identify disparities (e.g., by Ward or FBI Code), with interventions like stratified sampling to ensure fair representation across demographics—critical given historical over-policing concerns.
- **Integration Potential:** Aligns with CPD's Strategic Decision Support Centers (SDSCs) for dashboard deployment, using CLEAR system feeds for live scoring.

**Data Compliance and Ethical Framing:** Per City of Chicago open data terms, this derivative work acknowledges: "Data from [www.cityofchicago.org](www.cityofchicago.org); no claims on accuracy/timeliness; preliminary classifications may change; block-level privacy enforced; contact <DFA@ChicagoPolice.org> for queries." Risks like model bias or misuse are mitigated through transparent auditing, with no liability assumed by CPD. Focus on harm reduction (e.g., boosting clearances in under-served areas) positions it as a tool for restorative justice.

## Key Stakeholders and Quantifiable Impacts

| Stakeholder | Role | Projected Impact |
| ------------- | ------ | ------------------ |
| **CPD Operations** | Frontline dispatch, investigations | 10-15% faster clearances; \$20-50M annual savings in overtime/personnel (scaled from pilot efficiencies like Arlington PD's \$15K savings). Homicide clearance uplift to >60%. |
| **City Leadership (e.g., Mayor's Office)** | Budgeting, policy | Enhanced metrics for grants (e.g., via FBI NIBRS alignment); 20-30% crime rate reductions long-term per McKinsey AI benchmarks. |
| **Communities/Advocacy Groups** | Victims, residents in high-crime areas (e.g., 77 Community Areas) | Reduced underreporting via trust-building (e.g., equitable patrols); targeted interventions in hotspots like Garfield Park. |
| **External Partners (e.g., UChicago Crime Lab)** | Research, evaluation | Collaborative validation; precedents for scalable tools amid 2024 trends (e.g., 8% homicide drop). |

### ROI and Scalability

Initial development (data prep, modeling) costs ~\$50-100K; ROI within 1-2 years via efficiency gains, with scalability to API integration for mobile apps. Pilots in select districts could yield proof-of-concept in 6 months, informing broader adoption amid 2025's projected 5-21% crime declines.

citations:
<https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2/about_data>
<https://crimelab.uchicago.edu/resources/2024-end-of-year-analysis-chicago-crime-trends/>
<https://www.whitehouse.gov/articles/2025/08/yes-chicago-has-a-crime-problem-just-ask-its-residents/>
<https://www.illinoispolicy.org/chicago-violent-crime-trends-up-as-arrests-trend-down/>
<https://www.illinoispolicy.org/press-releases/violent-crime-up-18-arrests-down-43-in-chicago-over-10-years/>
