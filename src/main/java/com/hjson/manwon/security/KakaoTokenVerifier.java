package com.hjson.manwon.security;

import com.hjson.manwon.common.config.AuthProperties;
import com.hjson.manwon.common.exception.BusinessException;
import com.hjson.manwon.common.exception.ErrorCode;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

@Slf4j
@Component
public class KakaoTokenVerifier {

    private static final String TOKEN_INFO_URI = "https://kapi.kakao.com/v1/user/access_token_info";
    private static final String USER_ME_URI = "https://kapi.kakao.com/v2/user/me";
    private static final ParameterizedTypeReference<Map<String, Object>> MAP_TYPE =
            new ParameterizedTypeReference<>() {};

    private final RestClient client;
    private final long expectedAppId;

    public KakaoTokenVerifier(AuthProperties properties) {
        this.client = RestClient.builder().build();
        this.expectedAppId = properties.kakao().appId();
    }

    public KakaoUser verifyAndFetch(String kakaoAccessToken) {
        verifyAppId(kakaoAccessToken);
        Map<String, Object> me = call(USER_ME_URI, kakaoAccessToken, ErrorCode.AUTH_KAKAO_USERINFO_FAILED);
        return KakaoUser.from(me);
    }

    private void verifyAppId(String kakaoAccessToken) {
        Map<String, Object> info = call(TOKEN_INFO_URI, kakaoAccessToken, ErrorCode.AUTH_KAKAO_TOKEN_INVALID);
        Object appId = info.get("app_id");
        if (appId == null || !String.valueOf(appId).equals(String.valueOf(expectedAppId))) {
            throw new BusinessException(ErrorCode.AUTH_KAKAO_APP_MISMATCH);
        }
    }

    private Map<String, Object> call(String uri, String bearerToken, ErrorCode failureCode) {
        try {
            return client.get()
                    .uri(uri)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + bearerToken)
                    .retrieve()
                    .body(MAP_TYPE);
        } catch (RestClientResponseException e) {
            if (e.getStatusCode().value() == 401) {
                throw new BusinessException(ErrorCode.AUTH_KAKAO_TOKEN_INVALID);
            }
            log.warn("Kakao API {} failed: status={} body={}", uri, e.getStatusCode(), e.getResponseBodyAsString());
            throw new BusinessException(failureCode);
        } catch (Exception e) {
            log.warn("Kakao API {} call error", uri, e);
            throw new BusinessException(failureCode);
        }
    }

    public record KakaoUser(String providerUserId, String email, String nickname) {

        @SuppressWarnings("unchecked")
        static KakaoUser from(Map<String, Object> attributes) {
            Object id = attributes.get("id");
            if (id == null) {
                throw new BusinessException(ErrorCode.AUTH_KAKAO_USERINFO_FAILED);
            }
            String providerUserId = id.toString();

            Map<String, Object> account = (Map<String, Object>) attributes.get("kakao_account");
            String email = account != null ? (String) account.get("email") : null;
            String nickname = null;
            if (account != null) {
                Map<String, Object> profile = (Map<String, Object>) account.get("profile");
                if (profile != null && profile.get("nickname") != null) {
                    nickname = profile.get("nickname").toString();
                }
            }
            return new KakaoUser(providerUserId, email, nickname);
        }
    }
}
