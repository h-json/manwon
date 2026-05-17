package com.hjson.tenk.domain.badge;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@Entity
@Table(
        name = "badge",
        uniqueConstraints = @UniqueConstraint(
                name = "uk_badge_type_value",
                columnNames = {"type", "condition_value"}
        )
)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Badge {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "badge_id")
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(name = "type", nullable = false, length = 30)
    private BadgeType type;

    @Column(name = "condition_value", nullable = false)
    private int conditionValue;

    @Column(name = "icon_path", nullable = false, length = 255)
    private String iconPath;
}
