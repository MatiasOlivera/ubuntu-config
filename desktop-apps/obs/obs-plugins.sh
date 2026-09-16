#!/usr/bin/env bash

install_obs_plugins() {
    flatpak install flathub -y com.obsproject.Studio.Plugin.SceneSwitcher com.obsproject.Studio.Plugin.AdvancedMasks com.obsproject.Studio.Plugin.MoveTransition com.obsproject.Studio.Plugin.PipeWireAudioCapture com.obsproject.Studio.Plugin.SourceClone com.obsproject.Studio.Plugin.StrokeGlowShadow com.obsproject.Studio.Plugin.SourceCopy
}
