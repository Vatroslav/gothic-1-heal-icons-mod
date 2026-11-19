// Health & Mana Icons: marks inventory items that restore Health or Mana with
// the game's own Health and Mana icons in the top-right corner of the slot.
//
// What an item restores comes from its consume effects (the same data the
// game's AI reads when it picks a potion or food): a positive Heal magnitude
// means Health, a positive Mana magnitude means Mana. Items are matched to
// inventory slots by their name, so no inventory positions are involved.

// Settings > Game > Health & Mana Icons. The Options menu edits and saves the
// default object, so the extension reads the current value from there.
UCLASS(Config=GameUserSettings)
class UHealthManaIconsSettings : UGothicModExt_UserSettings
{
    default CategoryName = FText::FromString("Health & Mana Icons");

    UPROPERTY(Config)
    FModUserSettingsInt IconSize = FModUserSettingsInt(
        Value = 24,
        DefaultValue = 24,
        DisplayText = FText::FromString("Icon size"),
        MinValue = 12,
        MaxValue = 48);
}

// The icons added to one inventory slot widget. Slot widgets are pooled and
// reused for other items, so the icons stay and only their visibility changes.
class UHealthManaIconsRow : UObject
{
    UPROPERTY()
    UUserWidget Entry;

    UPROPERTY()
    UInventorySlotData Data;

    UPROPERTY()
    UHorizontalBox Box;

    UPROPERTY()
    UOverlay HealthBadge;

    UPROPERTY()
    UOverlay ManaBadge;

    UPROPERTY()
    TArray<UImage> Images;

    // Name of the item the icons were last set for. Empty for an empty slot.
    FString ShownName = "<none>";

    void ShowIcons(int Flags)
    {
        HealthBadge.SetVisibility((Flags & 1) != 0 ? ESlateVisibility::HitTestInvisible : ESlateVisibility::Collapsed);
        ManaBadge.SetVisibility((Flags & 2) != 0 ? ESlateVisibility::HitTestInvisible : ESlateVisibility::Collapsed);
    }

    void ApplySize(int Size)
    {
        for (auto Image : Images)
            Image.SetDesiredSizeOverride(FVector2D(float(Size), float(Size)));
    }
}

UCLASS(Abstract)
class UHealthManaIconsBase : UGothicModExt_WidgetExtension
{
    const int HealthFlag = 1;
    const int ManaFlag = 2;

    UPROPERTY()
    UListView Grid;

    UPROPERTY()
    TArray<UHealthManaIconsRow> Rows;

    // What each item restores, by the localization key of its name and, as a
    // fallback, by the displayed name.
    TMap<FString, int> FlagsByKey;
    TMap<FString, int> FlagsByName;

    bool bBound = false;
    int AppliedSize = -1;

    UFUNCTION(BlueprintOverride)
    bool RequiresTick() const
    {
        return true;
    }

    UFUNCTION(BlueprintOverride)
    void Tick(FGeometry MyGeometry, float32 InDeltaTime)
    {
        if (!bBound)
            BindToGrid();
        if (!bBound)
            return;

        int Size = Math::Clamp(UHealthManaIconsSettings.DefaultObject.IconSize.Value, 12, 48);
        bool bResize = Size != AppliedSize;
        AppliedSize = Size;

        for (int I = Rows.Num() - 1; I >= 0; --I)
        {
            auto Row = Rows[I];
            if (!IsValid(Row.Entry) || !IsValid(Row.Box))
            {
                Rows.RemoveAt(I);
                continue;
            }
            if (bResize)
                Row.ApplySize(Size);
            // The game can refill a slot's data in place, so compare every frame.
            RefreshRow(Row);
        }
    }

    UFUNCTION(BlueprintOverride)
    void Destruct()
    {
        if (bBound && IsValid(Grid))
        {
            Grid.BP_OnEntryInitialized.UnbindObject(this);
            Grid.BP_OnEntryReleased.UnbindObject(this);
        }
        bBound = false;
        Grid = nullptr;
        Rows.Empty();
    }

    void BindToGrid()
    {
        auto Inventory = Cast<UInventoryMain>(GetWidget());
        if (!IsValid(Inventory) || !IsValid(Inventory.TileView_Items) || !IsValid(Inventory.TileView_Items.TileView_Grid))
            return;

        // Read on every opening, so the names follow the game language.
        BuildCatalog();

        Grid = Inventory.TileView_Items.TileView_Grid;
        Grid.BP_OnEntryInitialized.AddUFunction(this, n"OnEntryInitialized");
        Grid.BP_OnEntryReleased.AddUFunction(this, n"OnEntryReleased");
        bBound = true;
        AppliedSize = -1;

        // Recreate the visible slots once, so slots that already exist also
        // pass through the callback above. The inventory itself is not rebuilt.
        Grid.RegenerateAllEntries();
    }

    void BuildCatalog()
    {
        FlagsByKey.Empty();
        FlagsByName.Empty();
        for (auto Type : UClass::GetAllSubclassesOf(UItemDefinition))
        {
            auto Item = Cast<UItemDefinition>(Type.GetDefaultObject());
            if (!IsValid(Item))
                continue;
            // Items that restore nothing are listed too, so a name match on them
            // never falls through to another item with the same displayed name.
            // Items sharing a name share their icons.
            int Flags = RestoreFlags(Item);
            int Existing = 0;
            FString Key = Item.m_Name.GetKey();
            if (!Key.IsEmpty())
            {
                FlagsByKey.Find(Key, Existing);
                FlagsByKey.Add(Key, Existing | Flags);
            }
            Existing = 0;
            // Not "Name": a local with that name shadows UObject's Name
            // accessor (GetName) and the script fails to compile.
            FString ItemName = Item.m_Name.ToString();
            if (!ItemName.IsEmpty())
            {
                FlagsByName.Find(ItemName, Existing);
                FlagsByName.Add(ItemName, Existing | Flags);
            }
        }
    }

    int RestoreFlags(UItemDefinition Item)
    {
        int Flags = 0;
        for (auto Effect : Item.m_OnConsumeEffects)
        {
            if (!IsValid(Effect))
                continue;
            float32 Amount = 0.0f;
            if (Effect.m_Magnitudes.Find(GameplayTag::GE_Param_Heal, Amount) && Amount > 0.0f)
                Flags = Flags | HealthFlag;
            Amount = 0.0f;
            if (Effect.m_Magnitudes.Find(GameplayTag::GE_Param_Mana, Amount) && Amount > 0.0f)
                Flags = Flags | ManaFlag;
        }
        return Flags;
    }

    int LookupFlags(UInventorySlotData Data)
    {
        int Flags = 0;
        FString Key = Data.m_Name.GetKey();
        if (!Key.IsEmpty() && FlagsByKey.Find(Key, Flags))
            return Flags;
        Flags = 0;
        FlagsByName.Find(Data.m_Name.ToString(), Flags);
        return Flags;
    }

    void RefreshRow(UHealthManaIconsRow Row)
    {
        FString ItemName = "";
        if (IsValid(Row.Data) && !Row.Data.m_IsEmpty)
            ItemName = Row.Data.m_Name.ToString();
        if (ItemName == Row.ShownName)
            return;
        Row.ShownName = ItemName;
        Row.ShowIcons(ItemName.IsEmpty() ? 0 : LookupFlags(Row.Data));
    }

    UFUNCTION()
    void OnEntryInitialized(UObject Item, UUserWidget EntryWidget)
    {
        auto Row = FindRow(EntryWidget);
        if (Row == nullptr)
        {
            Row = CreateRow(EntryWidget);
            if (Row == nullptr)
                return;
            Rows.Add(Row);
        }
        Row.Data = Cast<UInventorySlotData>(Item);
        Row.ShownName = "<none>";
        RefreshRow(Row);
    }

    UFUNCTION()
    void OnEntryReleased(UUserWidget EntryWidget)
    {
        auto Row = FindRow(EntryWidget);
        if (Row == nullptr)
            return;
        Row.Data = nullptr;
        Row.ShownName = "";
        Row.ShowIcons(0);
    }

    UHealthManaIconsRow FindRow(UUserWidget EntryWidget)
    {
        for (auto Row : Rows)
        {
            if (Row.Entry == EntryWidget)
                return Row;
        }
        return nullptr;
    }

    UHealthManaIconsRow CreateRow(UUserWidget EntryWidget)
    {
        if (!IsValid(EntryWidget))
            return nullptr;
        auto Content = Cast<UOverlay>(EntryWidget.GetWidgetFromName(n"Overlay_SlotContent"));
        if (!IsValid(Content))
            return nullptr;

        // The slot widget has no horizontal box of its own at this level, so a
        // horizontal box here is one this mod added before. Replace it.
        for (auto Child : Content.GetAllChildren())
        {
            if (IsValid(Cast<UHorizontalBox>(Child)))
                Child.RemoveFromParent();
        }

        auto Row = Cast<UHealthManaIconsRow>(NewObject(this, UHealthManaIconsRow));
        Row.Entry = EntryWidget;
        Row.Box = Cast<UHorizontalBox>(EntryWidget.ConstructWidget(UHorizontalBox));
        Row.HealthBadge = MakeBadge(Row, EntryWidget, TSoftObjectPtr<UTexture2D>(n"/Game/UI/Textures/Common/Icons/T_Icon_Health.T_Icon_Health"), FLinearColor(0.86, 0.10, 0.08, 1.0));
        Row.ManaBadge = MakeBadge(Row, EntryWidget, TSoftObjectPtr<UTexture2D>(n"/Game/UI/Textures/Common/Icons/T_Icon_Mana.T_Icon_Mana"), FLinearColor(0.22, 0.48, 1.0, 1.0));

        Row.Box.AddChildToHorizontalBox(Row.HealthBadge);
        Row.Box.AddChildToHorizontalBox(Row.ManaBadge).SetPadding(FMargin(2, 0, 0, 0));

        auto Placement = Content.AddChildToOverlay(Row.Box);
        Placement.SetHorizontalAlignment(EHorizontalAlignment::HAlign_Right);
        Placement.SetVerticalAlignment(EVerticalAlignment::VAlign_Top);
        // Same inset as the game's own corner icon in the top-left of the slot.
        Placement.SetPadding(FMargin(0, 26, 26, 0));
        Row.Box.SetVisibility(ESlateVisibility::HitTestInvisible);

        Row.ApplySize(Math::Clamp(UHealthManaIconsSettings.DefaultObject.IconSize.Value, 12, 48));
        Row.ShowIcons(0);
        return Row;
    }

    // One icon: a dark, slightly larger copy behind the coloured one keeps it
    // readable on bright item pictures.
    UOverlay MakeBadge(UHealthManaIconsRow Row, UUserWidget Owner, TSoftObjectPtr<UTexture2D> Texture, FLinearColor Tint)
    {
        auto Badge = Cast<UOverlay>(Owner.ConstructWidget(UOverlay));

        auto Shadow = Cast<UImage>(Owner.ConstructWidget(UImage));
        Shadow.SetBrushFromSoftTexture(Texture);
        Shadow.SetColorAndOpacity(FLinearColor(0.0, 0.0, 0.0, 0.85));
        Shadow.SetRenderScale(FVector2D(1.2, 1.2));
        auto ShadowSlot = Badge.AddChildToOverlay(Shadow);
        ShadowSlot.SetHorizontalAlignment(EHorizontalAlignment::HAlign_Center);
        ShadowSlot.SetVerticalAlignment(EVerticalAlignment::VAlign_Center);

        auto Icon = Cast<UImage>(Owner.ConstructWidget(UImage));
        Icon.SetBrushFromSoftTexture(Texture);
        Icon.SetColorAndOpacity(Tint);
        auto IconSlot = Badge.AddChildToOverlay(Icon);
        IconSlot.SetHorizontalAlignment(EHorizontalAlignment::HAlign_Center);
        IconSlot.SetVerticalAlignment(EVerticalAlignment::VAlign_Center);

        Row.Images.Add(Shadow);
        Row.Images.Add(Icon);
        return Badge;
    }
}

class UHealthManaIconsInventory : UHealthManaIconsBase
{
    default AddToWidgetOfClass = n"/Game/UI/ManagementUI/Inventory/W_Inventory_Main.W_Inventory_Main_C";
}
