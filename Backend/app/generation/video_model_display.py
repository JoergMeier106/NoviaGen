from __future__ import annotations


def resolve_video_model_display_name(
    *,
    high_diffusion_model_name: str | None = None,
    low_diffusion_model_name: str | None = None,
    fallback_model_id: str = "",
) -> str:
    high_name = str(high_diffusion_model_name or "").strip()
    low_name = str(low_diffusion_model_name or "").strip()

    if high_name and low_name:
        if high_name == low_name:
            return high_name
        return f"{high_name} + {low_name}"
    if high_name:
        return high_name
    if low_name:
        return low_name
    return str(fallback_model_id).strip()
