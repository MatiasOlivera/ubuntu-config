#!/usr/bin/env bash

install_obs_plugins() {
    local plugins=(SceneSwitcher AdvancedMasks MoveTransition PipeWireAudioCapture SourceClone StrokeGlowShadow SourceCopy)
    for plugin in "${plugins[@]}"; do
        flatpak install flathub -y "com.obsproject.Studio.Plugin.$plugin"
    done
}
