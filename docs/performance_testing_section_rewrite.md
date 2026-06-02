# 5.5 Performance Testing

Performance testing was conducted to evaluate the responsiveness of the deployed Alertrix prototype rather than only determining whether each function passed or failed. The evaluation focused on time-sensitive operations that affect disaster monitoring and alert response, including telemetry ingestion, backend processing, database persistence, alert visibility, notification dispatch, dashboard loading, and trend retrieval.

The performance test was conducted on 19 May 2026 using the deployed AWS backend in the `ap-southeast-5` region. Each measured scenario was executed for 10 trials. Latency was recorded in milliseconds using request timing from the test script. For the IoT ingestion path, telemetry was published to the same AWS IoT Core topic used by the ESP32 firmware, `alertrix/sensors/ingest`, and the test waited until the exact telemetry item became visible in DynamoDB. Therefore, this metric represents end-to-end cloud-side ingestion visibility, not pure MQTT transmission time only. The measured duration includes IoT Core message handling, IoT Rule invocation, Lambda execution, DynamoDB persistence, and the polling interval required to confirm the stored item. For HTTP and dashboard API paths, latency was measured from the start of the API request until a successful response was returned. For alert visibility, latency was measured from abnormal telemetry submission until the generated `alertId` appeared in the `/api/alerts` response. SESv2 and FCM were evaluated using the notification result returned by the backend during critical-alert trials.

**Table 5.4: Performance Evaluation Method**

| Performance Metric | Measurement Method | Endpoint / Evidence | Number of Trials |
|---|---|---|---:|
| IoT Core publish to DynamoDB visibility | Publish telemetry to AWS IoT Core and poll DynamoDB until the matching reading is found | Topic: `alertrix/sensors/ingest`; DynamoDB sensor readings table | 10 |
| HTTP fallback ingest response | Submit valid normal telemetry through API Gateway and measure response time | `POST /api/sensors/ingest` | 10 |
| Critical alert ingest response including notification dispatch | Submit critical telemetry and measure backend response time | `POST /api/sensors/ingest` | 10 |
| Abnormal reading to alert visible through dashboard API | Submit abnormal telemetry and poll alert API until the generated alert is returned | `GET /api/alerts` | 10 |
| Dashboard bootstrap API response | Measure initial dashboard data loading request | `GET /api/app/bootstrap` | 10 |
| Trend API response | Measure trend retrieval for water-level readings over the 24-hour range | `GET /api/trends?sensorType=waterLevel&range=24H` | 10 |
| Latest readings API response | Measure retrieval of latest sensor readings | `GET /api/readings/latest` | 10 |
| FCM dispatch result from critical alert trials | Check push notification result returned by backend alert response | Lambda response `pushResult` field | 10 |
| SESv2 alert email result from critical alert trials | Check email delivery result returned by backend alert response | Lambda response `emailResult` field | 10 |

**Table 5.5: Performance Evaluation Results**

| Performance Metric | Trials | Average (ms) | Minimum (ms) | Maximum (ms) | Success Rate |
|---|---:|---:|---:|---:|---:|
| IoT Core publish to DynamoDB visibility | 10 | 2070.5 | 1919 | 2532 | 100% |
| HTTP fallback ingest response | 10 | 101.4 | 75 | 238 | 100% |
| Critical alert ingest response including notification dispatch | 10 | 356.9 | 230 | 642 | 100% |
| Abnormal reading to alert visible through dashboard API | 10 | 547.2 | 276 | 1646 | 100% |
| Dashboard bootstrap API response | 10 | 221.9 | 59 | 1388 | 100% |
| Trend API response 24H water level | 10 | 163.4 | 41 | 939 | 100% |
| Latest readings API response | 10 | 195.6 | 62 | 1068 | 100% |
| FCM dispatch result from critical alert trials | 10 | N/A | N/A | N/A | 0% |
| SESv2 alert email result from critical alert trials | 10 | N/A | N/A | N/A | 100% |

The result shows that the backend API path was responsive during the test. The HTTP fallback ingest request achieved an average response time of 101.4 ms, while the critical alert ingest request, which includes threshold evaluation and notification dispatch logic, achieved an average response time of 356.9 ms. The abnormal-reading-to-alert-visibility measurement averaged 547.2 ms, meaning that alerts became visible through the dashboard API in less than one second on average during the test.

The IoT ingestion visibility metric required a longer time, with an average of 2070.5 ms and a maximum of 2532 ms. This value should not be interpreted as MQTT transmission time alone. It includes AWS IoT Core publish handling, IoT Rule invocation, Lambda execution, DynamoDB persistence, and polling until the item became visible in the database. Although it is slower than the direct HTTP fallback response, the result is still acceptable for the prototype because telemetry became available in DynamoDB within approximately three seconds for all 10 trials.

Dashboard-related API calls also showed acceptable response times. The dashboard bootstrap API averaged 221.9 ms, the 24-hour water-level trend API averaged 163.4 ms, and the latest readings API averaged 195.6 ms. Some maximum values were higher than the average, which may be caused by network variation, Lambda cold start behaviour, or AWS service response variation. However, all tested dashboard data requests completed successfully.

For notification performance, SESv2 email dispatch was successful in all 10 critical-alert trials, and the backend returned successful email delivery responses with message identifiers. However, FCM push notification dispatch did not succeed during this measured performance run. The backend returned an FCM push failure result for the tested critical alerts, so browser push delivery should be treated as a deployment or configuration limitation that requires further verification. Therefore, the report should not claim successful FCM delivery for this performance test unless a later retest confirms it.

Overall, the performance evaluation demonstrates that the implemented Alertrix prototype can ingest telemetry, process alert logic, store data, expose alerts to the dashboard, and send SESv2 email alerts within practical response times for a prototype disaster monitoring system. The main remaining performance-related issue is the unsuccessful FCM push dispatch observed during the measured test run.

**Figure 5.X: Lambda Execution Log Used for Performance Measurement**

**Figure 5.X: Browser Dashboard Response During Alert Test**
