# Body Composition Algorithm · Public Explanation

> **Why make this public**: if you never tell users how a number like body fat percentage is computed,
> then they can only "believe" it — and that is not what health data should look like.
>
> This document lays out **every line of the formulas** in `lib/core/bodycomp.dart`,
> and states explicitly which parts are **the original formulas from published papers** and which are **calibration coefficients we reverse-engineered from measurements**.
>
> **The conclusion in one sentence**: this scale **does not measure fat directly**. It measures **resistance**,
> and the fat percentage is **estimated** from that resistance (or from height, weight and age).

---

## 1. The principle first: why measuring resistance yields fat

### 1.1 Human tissue does not conduct alike

| Tissue | Water content | Conductivity |
| --- | --- | --- |
| muscle, blood, organs | high (about 70~75%) | **good** (contains electrolytes, like salt water) |
| fat | low (about 10~20%) | **poor** (like plastic) |
| bone | low | poor |

So: **at the same weight, a person with more fat has a higher resistance**. That is the whole foundation of BIA (bioelectrical impedance analysis).

### 1.2 How the scale takes the measurement

```
       two feet, each with two electrode pads (4 in total)

   left front ─┐              ┌─ right front
               │   ╭──────╮   │
               │   │ deck │   │
               │   ╰──────╯   │
   left back  ─┘              └─ right back

Current path: the electrodes under one foot emit a very weak AC current (<1mA, imperceptible)
          → through the calf, thigh and pelvis → out again through the other foot's electrode
          → the voltage drop is measured in between → Ohm's law gives the impedance (Ω)
```

**The crucial point**: both feet must be bare and press all four electrodes at the same time for the circuit to close.
One foot, socks on, or a very dry sole → the measured impedance is **0**, and body fat percentage cannot be computed at all.

> This is not something software can control. Any claim that "sending some command turns on the impedance" is wrong —
> we verified it with an A/B control experiment (see pitfall 7 in the [protocol document](PROTOCOL.md)).

### 1.3 The raw data this scale hands us

In the locked packet at the end of a measurement the scale gives **two ADC values** (you can read them as the raw readings of the left and right channels):

```
impedance1 = (d[4] << 8 | d[5])   ← unit is ohms
impedance2 = (d[6] << 8 | d[7])
```

The normal range is roughly **100 ~ 1500 Ω**. Any value outside that range is treated as invalid.

---

## 2. Step one: combine the two impedances into one

The formulas in the papers all accept only **one** impedance value, but the scale hands us two. Our approach:

```
combined impedance R = (impedance1 + impedance2) × 0.675
```

### Where that 0.675 comes from

⚠️ **This coefficient is not in any paper; we reverse-engineered it from measurements**.

Method: take the body fat percentage the official Ant Health app displayed at the same moment, and back-solve which R makes the formula agree.
After fitting several data sets we found that about 0.675 hits reliably (for example 55.75kg + impedance [430, 387] → the official app shows 22.2%).

**Why there are two ADCs**: one channel may be 50kHz and the other a different frequency (a common arrangement in multi-frequency BIA),
and combining the two usually serves to cancel the effect of contact resistance. But the vendor has not published this, so our reading is inference only.

### Validity check

```
R counts as a valid impedance only when the combined value falls between 100 ~ 1500 Ω
```

---

## 3. BMI (the only metric that does not depend on estimation)

```
BMI = weight(kg) ÷ height(m)²
```

Example: 55.75kg, 163cm → 55.75 ÷ 1.63² = **21.0**

**BMI contains neither sex nor age**. This is the World Health Organization (WHO) definition,
so every piece of software should compute the same BMI (as long as weight and height are the same).

So: switching sex leaves BMI unchanged — that is **correct behaviour**, not a bug.

---

## 4. Male body fat percentage: the Deurenberg formula (no impedance)

```
body fat percentage(%) = 1.10 × BMI + 0.23 × age − 11.22
```

**Source**: the race-corrected formula published by Deurenberg et al. in 1991 (the Japanese-population version).
These are **the original formulas from a published paper**; we use the fixed coefficients unchanged.

**Note: the male formula contains no impedance**. That is, given height, weight and age,
a male body fat percentage can still be computed even if the electrodes were not properly stepped on and the impedance is 0.

**Measured cross-check**: a 79.8kg male sample → computed 25.4%, consistent with what the official app displays.

Model marker: `deurenberg_jp_male`

---

## 5. Female body fat percentage: the Segal formula (impedance required)

Women take a different formula, and it needs impedance.

### 5.1 First compute fat-free mass (FFM, Fat-Free Mass)

```
FFM = weight − the weight of the fat    ← i.e. muscle + bone + water + organs together
```

The Segal formula does not give the body fat percentage directly; it estimates FFM first and then back-solves with `100 × (weight − FFM) ÷ weight`.

### 5.2 Two branches: try 3C first, then 3D

**Branch A (the 3C form, for people with body fat < 30%)**

```
FFM_A = 10.43485
      + 0.00064602 × height²(cm²)
      − 0.01397   × R(combined impedance)
      + 0.42087   × weight(kg)
```

Compute A first, then back-solve the body fat percentage from it; **if the result is < 30%, use that value**.

**Branch B (the 3D form, for people with body fat ≥ 30%)**

```
FFM_B = 9.37938
      + 0.00091186 × height²(cm²)
      − 0.01466   × R
      + 0.29990   × weight
      − 0.07012   × age
```

> Why two segments? Because the Segal formula is originally two regression lines fitted for different degrees of obesity;
> for obese people the A form systematically underestimates FFM. Splicing the two segments is what the paper intended.

**Source**: the formula published by Segal et al. in 1988 in the *American Journal of Clinical Nutrition*.
The original coefficients are public, and we use them directly.

**Note the height unit**: the height in the formula is in **cm**, so squaring it gives cm² (e.g. 163² = 26569).
It is not m². Getting this wrong is a factor of 10000.

### 5.3 Plausibility clamping

```
FFM is clamped between 35% and 97% of body weight
```

To prevent extreme inputs (say 100Ω impedance paired with a 30kg body weight) from producing absurd results.

**Measured cross-check**: 55.75kg + impedance [430, 387] → combined R = 551Ω → computed 22.2%, consistent with the official app.

Model marker: `segal_3c_female_lt30` / `segal_3d_female_ge30`

### 5.4 The fallback for women when there is no impedance

```
body fat percentage(%) = 1.10 × BMI + 0.23 × age − 5.4
```

This is the **female version** of the Deurenberg formula (the male version ends in −11.22, the female one in −5.4).
Note the contrast with the male formula: for the same BMI and age a woman computes **5.82 percentage points higher** —
which agrees with physiological fact (women's normal body fat percentage is higher than men's in the first place).

Model marker: `deurenberg_jp_female`

---

## 6. Final clamping

```
male body fat percentage clamped to 3% ~ 60%
female body fat percentage clamped to 8% ~ 60%
```

The lower bounds differ because male body fat below 3% is almost physiologically impossible (the competitive bodybuilding limit is around 4~5%),
and female body fat below 8% affects the endocrine system. Anything above 60% is basically a measurement error.
---

## 7. The remaining metrics: all "derived" from body fat percentage

⚠️ **One thing to be clear about first**: this scale measures only two quantities, **weight** and **impedance**.
Every metric below is **derived** from the body fat percentage computed in the step above; none of them is measured separately.

So their credibility should be understood in this order:

```
credibility: weight (measured directly) > BMI (pure mathematics) > body fat percentage (formula estimate) > other metrics (derived twice)
```

### 7.1 Fat mass / fat-free mass

```
fat mass(kg)      = weight × body fat %
fat-free mass(kg) = weight − fat mass
```

Pure arithmetic, no additional assumptions.

### 7.2 Bone mass: a fixed percentage

```
bone mass% = male 4.5%   /   female 4.0%
bone mass(kg) = weight × bone mass%
```

⚠️ **This is a hard-coded constant, not a measurement**. Real bone density requires DEXA (X-ray) to measure;
the "bone mass" of any home body-fat scale is an estimate taken from population averages.
Our values come from reverse-engineering what the official app displays.

### 7.3 Muscle mass: obtained by subtraction

```
muscle% = 100 − body fat% − bone mass%      (result clamped to 20% ~ 95%)
muscle mass(kg) = weight × muscle%
```

The logic is "whatever is neither fat nor bone counts as muscle".
Strictly speaking that remainder also holds organs, water and connective tissue, but vendors habitually classify it this way.

### 7.4 Body water percentage: fat-free mass × coefficient

```
water% = (100 − body fat%) × coefficient
coefficient: male 0.7185   /   female 0.8475
(result clamped to 25% ~ 80%)
```

Physiological basis: fat-free tissue (muscle, organs) is about 73% water; adipose tissue is about 10~20% water.

⚠️ The female coefficient 0.8475 is markedly higher than the usual 0.73; it is the result of reverse-engineering the official app.
The vendor probably has its own correction model; we follow the measured value.

### 7.5 Protein: a straight proportion of body weight

```
protein mass(kg) = weight × coefficient
coefficient: male 0.163   /   female 0.05
```

⚠️ **Here is one point that needs to be called out**:

| Source | Male protein share | Female protein share |
| --- | --- | --- |
| general physiology | about 16~18% | about 16~18% |
| our implementation | 0.163 (reasonable) | **0.05 (clearly too low)** |

The female 0.05 was reverse-engineered from the values the official app displays,
**and physiologically the number does not look reasonable** — it makes a 55.75kg woman show only 2.8kg of protein,
whereas the real figure should be around 9kg.

We keep it in order to "stay consistent with the official app"; if you care more about physiological plausibility,
you can change that coefficient to around 0.16. **Cite this item with caution.**

### 7.6 Skeletal muscle percentage: muscle mass × coefficient

```
skeletal muscle% = muscle% × coefficient
coefficient: male 0.548   /   female 0.651
(result clamped to 10% ~ 70%)
```

"Skeletal muscle" is the part of the muscle attached to bone (as opposed to cardiac and smooth muscle).
It is usually 55~65% of total muscle; the different male and female coefficients are the result of reverse-engineering.

### 7.7 Subcutaneous fat: body fat × coefficient

```
subcutaneous fat% = body fat% × coefficient
coefficient: male 0.7165   /   female 0.72
(result clamped to 1% ~ body fat%)
```

Body fat splits into "subcutaneous fat" (the layer you can pinch) and "visceral fat" (wrapped around the organs).
This coefficient says that about 72% of the fat is subcutaneous.

---

## 8. The complete computation flow (pseudocode)

```
input: weight W(kg), height H(cm), age A, sex, impedance [i1, i2]

① BMI = W ÷ (H/100)²

② combined impedance R = (i1 + i2) × 0.675
   if R is outside 100~1500 → treat as no valid impedance

③ compute the body fat percentage bf:
   if sex=male:
       bf = 1.10×BMI + 0.23×A − 11.22          ← no impedance needed
   else (female):
       if R is valid:
           FFM_A = 10.43485 + 0.00064602×H² − 0.01397×R + 0.42087×W
           if 100×(W−FFM_A)/W < 30  →  bf = 100×(W−FFM_A)/W
           else:
               FFM_B = 9.37938 + 0.00091186×H² − 0.01466×R + 0.29990×W − 0.07012×A
               bf = 100×(W−FFM_B)/W
           where FFM is clamped to W×0.35 ~ W×0.97
       else (no impedance):
           bf = 1.10×BMI + 0.23×A − 5.4       ← female fallback formula

④ clamp bf: male 3~60, female 8~60

⑤ derived:
   fat mass          = W × bf/100
   fat-free mass     = W − fat mass
   bone mass%        = male 4.5 / female 4.0
   muscle%           = 100 − bf − bone mass% (clamped 20~95)
   water%            = (100−bf) × (male 0.7185 / female 0.8475) (clamped 25~80)
   protein mass      = W × (male 0.163 / female 0.05)
   skeletal muscle%  = muscle% × (male 0.548 / female 0.651) (clamped 10~70)
   subcutaneous fat% = bf × (male 0.7165 / female 0.72) (clamped 1~bf)

⑥ all outputs keep 1 decimal place
```

Corresponding code: `lib/core/bodycomp.dart` (76 lines, no external dependencies, testable on its own)

---

---

## 8.5 Measured output: what the same data yields for a man and for a woman

Take the data set `55.75kg / 163cm / 24 years old / impedance 430+387` and run the whole algorithm:

| Metric | Male formula | Female formula | Difference | Note |
| --- | --- | --- | --- | --- |
| BMI | **21.0** | **21.0** | **identical** | pure mathematics, no sex |
| body fat percentage | 17.4% | 22.2% | +4.8 pp | men and women take different formulas |
| body water percentage | 59.4% | 65.9% | +6.5 pp | women's fat-free tissue holds water at a higher coefficient |
| skeletal muscle percentage | 42.8% | 48.0% | +5.2 pp | coefficient 0.548 vs 0.651 |
| subcutaneous fat | 12.5% | 16.0% | +3.5 pp | rises with the body fat percentage |
| protein mass | **9.1 kg** | **2.8 kg** | 6.3 kg apart | ⚠️ the known doubt about the female coefficient 0.05 (see §7.5) |

Model markers: male `deurenberg_jp_male` · female `segal_3c_female_lt30` (combined impedance 551.5Ω)

> This table wants to make two things clear:
> 1. **BMI comes out exactly the same** — that it does not change when you switch sex is by design
> 2. **the protein row is the anomaly** — men and women should not differ by three times; that is a leftover of the reverse-engineered coefficients

## 9. Where the formulas come from

| Formula | Source | Published original formula? |
| --- | --- | --- |
| BMI | WHO definition | ✅ original formula |
| male body fat Deurenberg | Deurenberg et al. 1991 (Japanese-population correction) | ✅ original formula |
| female body fat Segal 3C/3D | Segal et al. 1988, *AJCN* | ✅ original formula |
| female fallback Deurenberg | the same formula with female parameters | ✅ original formula |
| **combined impedance × 0.675** | reverse-engineered by us from the official app | ❌ **calibration coefficient** |
| **water coefficient 0.7185 / 0.8475** | as above | ❌ **calibration coefficient** |
| **protein coefficient 0.163 / 0.05** | as above (the female value is doubtful) | ❌ **calibration coefficient** |
| **skeletal muscle coefficient 0.548 / 0.651** | as above | ❌ **calibration coefficient** |
| **subcutaneous fat coefficient 0.7165 / 0.72** | as above | ❌ **calibration coefficient** |
| **bone mass 4.5% / 4.0%** | as above | ❌ **fixed constant** |

> Honest disclosure: the rows marked ❌ above **have no paper behind them**; they were reverse-engineered from the values the official app displays.
> They bring this app close to the official results, but they do not represent physiological truth.

---

## 10. The limits of this algorithm (important)

### 10.1 It differs from the scale's screen by a few tenths of a percentage point

The scale screen uses the vendor's **proprietary algorithm** (not published). We use public formulas plus calibration coefficients,
so the two sides differ by roughly **0.3~0.5 percentage points**.

**BMI is always identical** (pure mathematics; there is no room for algorithmic disagreement).

### 10.2 Impedance is heavily affected by body water

For the same body, impedance can differ by tens of ohms between states, which corresponds to a 2~5 percentage point difference in body fat:

| Situation | Impedance | Body fat reading |
| --- | --- | --- |
| just got out of bed in the morning (slightly dehydrated) | higher | higher |
| just drank water / just finished exercising (blood engorged) | lower | lower |
| just had a shower (moist skin) | lower | lower |
| dry soles in winter | higher | higher |

**Correct usage**: always measure in the same state (for example every morning after getting up, after urinating and before drinking water),
and watch the **trend** instead of a single reading.

### 10.3 People this does not suit

- pregnant women (body fluid distribution is unusual)
- athletes / bodybuilders (at very low body fat the formula extrapolates poorly)
- patients with oedema, ascites or on dialysis (abnormal body fluids)
- children and adolescents (the formulas do not apply to growth stages)
- people with an implanted cardiac pacemaker (risk from the weak current, **absolutely do not use**)

### 10.4 It is not a medical device

Every number is an **estimate**, for personal trend reference only; it must not be used for diagnosis, treatment or any medical decision.
For accurate body composition, get a DEXA (dual-energy X-ray absorptiometry) or MRI scan.

---

## 11. References

1. **Segal KR, et al.** "Lean body mass estimation by bioelectrical impedance analysis:
   a four-site validation study." *Am J Clin Nutr.* 1988;47(1):7-14.
2. **Deurenberg P, et al.** "Body mass index as a measure of body fatness:
   age- and sex-specific prediction formulas." *Br J Nutr.* 1991;65(2):105-114.
3. **Deurenberg-Yap M, et al.** "The paradox of low body mass index and high body fat
   percentage among Chinese, Malays and Indians in Singapore." *Int J Obes.* 2000.
4. World Health Organization. "BMI classification."

> The calibration coefficients (0.675 / 0.7185 / 0.8475 / 0.163 / 0.05 / 0.548 / 0.651 / 0.7165 / 0.72)
> have no literature source; they come from this project's reverse-engineering of the values displayed by the official Ant Health app,
> and are recorded in the measurement notes of the [protocol document](PROTOCOL.md).
