package com.hjson.tenk.common.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "tenk.upload")
public record StorageProperties(String baseDir) {
}
