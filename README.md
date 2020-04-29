# EnerTalk
## About
 EnerTalk QuickApp for Fibaro HC3

## 사전 준비
    1. EnerTalk 가입
       - https://developer.enertalk.com/my-apps/
    2. Client Id, Client Secret 발급 및 Redirect URL 설정
       - Redirect URL: http://localhost
    3. code 발급
       - https://auth.enertalk.com/authorization?client_id={Client Id}&response_type=code&redirect_uri=http://localhost
       - 주소창에 위의 주소입력 후 EnerTalk 개발센터 로그인 후 리다이렉트된 code값 복사    
       # http://localhost?code=XXXX ( code값은 XXXX )
  
## Installation
    0. 사전준비를 통해 Client Id, Client Secret, code 3개의 값을 준비하고 진행 
    1. HC3 > Settings > 5. Devices > Add Device > Other Device를 선택
    2. Quick App 클릭 > 장치의 Name 및 Room 선택 > Device Type "Binary switch" 선택 후 저장
    3. 생성된 장치로 선택 후 Edit & Preview 탭으로 이동하여 Edit 화면으로 이동
    4. EnerTalk.lua의 내용을 Edit 화면에 넣은 후 저장
    5. Variables 탭으로 이동 후 변수를 넣고 저장
   
```yaml
clientId                  -- 사전준비에서 발급받은 client id 입력
clientSecret              -- 사전준비에서 발급받은 Client Secret 입력
code                      -- 사전준비에서 발급받은 code 입력
interval_today            -- 어제, 오늘 요금 및 사용량 데이터를 조회하는 간격 (초)
interval_real             -- 실시간 사용량 데이터를 조회하는 간격 (초)
interval_accrue           -- 이번달 현재까지의 요금 및 사용량 데이터를 조회하는 간격 (초)
interval_estimate         -- 이번달 예상 요금 및 사용량 데이터를 조회하는 간격 (초)
siteId                    -- 자동생성 (수정 X)
accessToken               -- 자동생성 (수정 X)
refreshToken              -- 자동생성 (수정 X)
```
**# 부모 Device Show in History 값에 따라 하위 Device 또한 저장 여부를 결정**