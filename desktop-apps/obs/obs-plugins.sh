#!/usr/bin/env bash

install_obs_plugins() {
    # Advanced Scene Switcher
    flatpak install flathub -y com.obsproject.Studio.Plugin.SceneSwitcher

    # Advanced Masks
    flatpak install flathub -y com.obsproject.Studio.Plugin.AdvancedMasks

    # Move Transition
    flatpak install flathub -y com.obsproject.Studio.Plugin.MoveTransition

    # PipeWire Audio Capture
    flatpak install flathub -y com.obsproject.Studio.Plugin.PipeWireAudioCapture

    # Source Clone
    flatpak install flathub -y com.obsproject.Studio.Plugin.SourceClone

    # Stroke Glow Shadow
    flatpak install flathub -y com.obsproject.Studio.Plugin.StrokeGlowShadow

    # Source Copy
    flatpak install flathub -y com.obsproject.Studio.Plugin.SourceCopy
}
