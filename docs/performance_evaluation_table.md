| Performance Metric | Trials | Average (ms) | Minimum (ms) | Maximum (ms) | Success Rate |
|---|---:|---:|---:|---:|---:|
| IoT Core MQTT publish to DynamoDB visible | 10 | 2070.5 | 1919 | 2532 | 100% |
| HTTP fallback ingest response | 10 | 101.4 | 75 | 238 | 100% |
| Critical alert ingest response including notification dispatch | 10 | 356.9 | 230 | 642 | 100% |
| Abnormal reading to alert visible through dashboard API | 10 | 547.2 | 276 | 1646 | 100% |
| Dashboard bootstrap API response | 10 | 221.9 | 59 | 1388 | 100% |
| Trend API response 24H water level | 10 | 163.4 | 41 | 939 | 100% |
| Latest readings API response | 10 | 195.6 | 62 | 1068 | 100% |
| FCM dispatch result from critical alert trials | 10 | N/A | N/A | N/A | 0% |
| SESv2 alert email result from critical alert trials | 10 | N/A | N/A | N/A | 100% |
