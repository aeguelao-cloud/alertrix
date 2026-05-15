# SRD Feedback Integration Notes

This document maps the major comments from `System Requirements and Design Report-Commented.pdf` to the revised final report draft and supporting documentation. It is a working checklist for turning the SRD into the final report.

## Main SRD Problems Identified

| Area | SRD feedback / issue | How it is handled in the final report draft |
|---|---|---|
| Citation style | References were placed after full stops or used inconsistently. | Final report keeps references as placeholders. When citations are added, use one consistent style, e.g. IEEE, and place citations before the full stop. |
| Unclear sensor scope | The SRD used phrases such as "temperature or humidity sensor", and also mentioned gas, fire, home monitoring, earthquake, and broad environmental factors. | Final report scope is narrowed to what code confirms: ESP32, DHT11 temperature/humidity reading, analog water level, buzzer, AWS IoT, Lambda, DynamoDB, FCM, Flutter Web. Humidity cloud alerting and physical vibration sensing are marked as not implemented. |
| Predictive analysis / ML ambiguity | The SRD used "predictive analysis", which implies machine learning or deep learning. | Final report explicitly states that Alertrix uses rule-based threshold analysis, not ML prediction. |
| Weak background | Background was too short. | Chapter 1 background was expanded to explain IoT sensing, cloud-assisted processing, storage, alerts, and dashboard workflow. |
| Problem statement comparison | The SRD compared traditional manual systems with the proposed system, which the comment said was weak. | Problem statements were rewritten to compare against limitations of existing IoT/cloud monitoring prototypes and to require support from literature metrics. |
| Objectives too broad | One SRD objective explained the whole system instead of being a measurable objective. | Objectives are rewritten as measurable implementation/evaluation objectives with status. |
| Missing heading explanation | Some headings were left without explanation. | Final report chapters include explanatory paragraphs before/after tables and diagrams. |
| Poor figure quality | Previous architecture/module figures had quality and margin issues. | `docs/diagrams.md` contains Mermaid diagrams that can be exported cleanly. The final report reminds that every figure must be referenced in text. |
| Module diagram too simple | Previous module diagram did not show sub-modules such as sign up/login. | `docs/diagrams.md` module diagram includes firmware, backend, data, UI, login/register/reset, dashboard, trends, alerts, settings, admin management, work orders, FCM, and sound. |
| Missing Chapter 2 in report organization | SRD missed Chapter 2 in organization. | Final report organization includes Chapter 2. |
| Literature review too weak | SRD only referred to a few papers and lacked a comparison table. | Chapter 2 now contains a 20-study comparison table template and marks literature citations as `[To be completed]`. |
| Repeated same reference | SRD overused the same reference. | Final report marks related work citations as pending and warns that specific sources must support each problem/gap. |
| Alertrix mentioned too early in literature review | Feedback said existing works should be reviewed first, then Alertrix contribution at the end. | Chapter 2 is structured as topic review first, comparison table, research gap, then contribution. |
| Vague words | SRD used informal/vague terms such as "others", "all the thing", and unclear "different platforms". | Final report uses specific tables and avoids those expressions. |
| Active voice | Feedback requested less active/personal academic writing. | Draft uses mostly formal/passive academic style. Some sections may still be polished during final Word editing. |
| Functional requirements format | SRD requirements section should be presented as a table. | Chapter 3 functional and non-functional requirements are tables. |
| Gas/flame detector inconsistency | SRD mentioned gas/flame detector for flood monitoring. | Final report removes gas/flame detector claims. |
| Diagram arrows/margins | Some diagrams had no direction or were outside margins. | Mermaid diagrams use directed arrows and should be exported to fit page margins. |
| Data source for training/test set | SRD included training/test terminology, which may imply ML. | Final report does not claim ML training/test datasets. Testing is described as functional, integration, performance, reliability, and false alarm evaluation. |

## Final Report Files Affected

| File | Purpose after SRD integration |
|---|---|
| `docs/FYP_Final_Report_Draft.md` | Main report draft. Chapter 1, Chapter 2, and Chapter 3 were revised to address SRD comments. |
| `docs/implementation_summary.md` | Confirms what is actually implemented in code and what is not implemented. |
| `docs/api_endpoint_table.md` | Supports system interface design and implementation sections. |
| `docs/database_design.md` | Supports database design section. |
| `docs/testing_and_evaluation.md` | Replaces vague "training/test set" wording with actual testing and evaluation structure. |
| `docs/diagrams.md` | Provides clean diagrams for architecture, modules, alert sequence, database, and user flow. |
| `docs/screenshot_checklist.md` | Lists required screenshots/evidence for final report and appendices. |

## Recommended Final Report Structure After Integration

| Final report chapter | Use these generated files |
|---|---|
| Chapter 1: Introduction | `FYP_Final_Report_Draft.md` |
| Chapter 2: Literature Review and Related Work | `FYP_Final_Report_Draft.md`; fill 20-paper comparison table manually |
| Chapter 3: System Analysis and Design | `FYP_Final_Report_Draft.md`, `database_design.md`, `diagrams.md`, `api_endpoint_table.md` |
| Chapter 4: System Implementation | `FYP_Final_Report_Draft.md`, `implementation_summary.md`, `api_endpoint_table.md` |
| Chapter 5: Testing and Evaluation | `testing_and_evaluation.md` |
| Chapter 6: Results and Discussion | `FYP_Final_Report_Draft.md`, screenshots and measured results |
| Chapter 7: SDG Alignment | `FYP_Final_Report_Draft.md` |
| Chapter 8: Conclusion and Future Work | `FYP_Final_Report_Draft.md` |
| Appendices | `screenshot_checklist.md`, exported diagrams, API table, database table, test evidence |

## Content That Should Be Removed or Avoided From the Old SRD

Do not copy these old SRD claims into the final report unless the code/evidence is later added:

| Old SRD topic | Reason |
|---|---|
| Gas leak / flame detector | Not implemented and inconsistent with current Alertrix code. |
| Fire-risk monitoring | Not implemented as a system feature; temperature threshold exists but not a full fire-risk system. |
| Earthquake detection | Not implemented. Vibration backend metric exists, but physical vibration sensor is not implemented in firmware. |
| Machine learning / predictive analytics | Not implemented. |
| SMS notification | Not implemented. FCM and SES email are implemented. |
| "All kinds of devices" / vague multi-platform claims | Not specific. Current frontend is Flutter Web with platform folders generated by Flutter. |
| Home monitoring | Not the confirmed scope. Use pilot monitoring site / disaster response prototype. |
| Humidity cloud alerting | Firmware reads humidity locally, but backend does not store humidity as a metric. |

## Remaining Work Before Final Submission

| Work item | Status |
|---|---|
| Add 15-20 real related works with citations. | `[To be completed]` |
| Fill comparison table with measured metrics from papers. | `[To be completed]` |
| Export Mermaid diagrams as high-resolution figures. | `[To be completed]` |
| Insert figure/table captions and refer to each figure/table in the text. | `[To be completed]` |
| Collect prototype, AWS, DynamoDB, Lambda, FCM, and dashboard screenshots. | `[To be completed]` |
| Run and record functional, integration, latency, reliability, and false alarm tests. | `[To be completed]` |
| Update or fix the failing Flutter widget test if automated test evidence is required. | `[To be completed]` |
| Decide whether to implement a real vibration sensor or keep it clearly marked as not implemented. | `[To be completed]` |

## Suggested Wording Corrections

Use these replacements when polishing the final report:

| Avoid | Use instead |
|---|---|
| "predictive analysis" | "rule-based threshold analysis" |
| "temperature or humidity sensor" | "DHT11 temperature/humidity sensor" |
| "text messages, mobile notifications, or soundings" | "Firebase web push notifications, SES email alerts, and local buzzer/dashboard sound" |
| "earthquakes or rising water levels" | "rising water level and abnormal environmental readings" |
| "all the thing" | "the required telemetry, alert, dashboard, and notification components" |
| "different platforms" | "Flutter Web dashboard" |
| "home monitoring" | "pilot monitoring site" |
