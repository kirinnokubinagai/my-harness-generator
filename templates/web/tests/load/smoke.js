// 概要: k6 smoke test。
//       PR → stage CI で実行されるベースライン (`templates/github/workflows/k6-smoke.yml`)。
//       真の負荷試験 (sustained / realistic mix) はローンチ前にローカルで別途実施。
//
// しきい値:
//   - エラー率 1% 未満
//   - p95 レイテンシ 500ms 未満
//   - p99 レイテンシ 1000ms 未満

import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m',  target: 10 },
    { duration: '30s', target: 0  },
  ],
  thresholds: {
    http_req_failed:   ['rate<0.01'],
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8787';

export default function () {
  const res = http.get(`${BASE_URL}/healthz`);
  check(res, {
    'status is 200': (r) => r.status === 200,
    'body has ok':   (r) => r.json('ok') === true,
  });
  sleep(1);
}

export function handleSummary(data) {
  return { 'summary.json': JSON.stringify(data, null, 2) };
}
